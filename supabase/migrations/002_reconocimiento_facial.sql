-- =====================================================================
--  002_reconocimiento_facial.sql  —  Rostro con IA en el kiosco
--
--  Correr DESPUÉS de 001_reloj_checador.sql, una sola vez, en el SQL
--  Editor del proyecto arypsa-rh. Se puede volver a correr sin romper nada.
--
--  Qué agrega
--  ----------
--  * rh_rostros: el "vector facial" de cada empleado (192 números que saca
--    la red MobileFaceNet dentro de la tablet). No se guarda la foto.
--  * rh_sedes.modo_biometrico: 'cualquiera' | 'respaldo' | 'doble'.
--  * rh_sedes.umbral_rostro: qué tan parecida debe ser la cara (distancia
--    máxima). Más bajo = más estricto.
--  * rh_empleados.rostros: contador (RH no lee rh_rostros directo).
--  * rh_checadas.metodo acepta 'rostro' y 'rostro+huella'.
--  * Las funciones del kiosco ahora bajan/suben rostros.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------
create table if not exists public.rh_rostros (
  id              uuid primary key default gen_random_uuid(),
  empleado_id     uuid not null references public.rh_empleados(id) on delete cascade,
  modelo          text not null,              -- 'mobilefacenet-192'
  vector          real[] not null,            -- normalizado (norma 1)
  calidad         integer,
  dispositivo_id  uuid,
  creado_at       timestamptz not null default now(),
  check (array_length(vector, 1) between 64 and 1024)
);
create index if not exists rh_rostros_emp on public.rh_rostros (empleado_id);

alter table public.rh_empleados add column if not exists rostros integer not null default 0;

alter table public.rh_sedes add column if not exists modo_biometrico text not null default 'respaldo';
alter table public.rh_sedes drop constraint if exists rh_sedes_modo_biometrico_check;
alter table public.rh_sedes add constraint rh_sedes_modo_biometrico_check
  check (modo_biometrico in ('cualquiera','respaldo','doble'));
alter table public.rh_sedes add column if not exists umbral_rostro real not null default 0.85;
alter table public.rh_sedes drop constraint if exists rh_sedes_umbral_rostro_check;
alter table public.rh_sedes add constraint rh_sedes_umbral_rostro_check
  check (umbral_rostro between 0.3 and 1.4);

alter table public.rh_checadas drop constraint if exists rh_checadas_metodo_check;
alter table public.rh_checadas add constraint rh_checadas_metodo_check
  check (metodo in ('lector','rostro','rostro+huella','biometria_movil'));

alter table public.rh_rostros enable row level security;
revoke all on public.rh_rostros from anon, authenticated;
-- Igual que rh_huellas: ningún grant, solo las funciones la tocan.

-- ---------------------------------------------------------------------
-- RH
-- ---------------------------------------------------------------------
create or replace function public.rh_borrar_rostros(p_empleado uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not rh_es_rh() then raise exception 'sin_permiso'; end if;
  delete from rh_rostros where empleado_id = p_empleado;
  update rh_empleados set rostros = 0 where id = p_empleado;
end $$;

-- La baja ahora también borra el rostro.
create or replace function public.rh_dar_baja(p_empleado uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not rh_es_rh() then raise exception 'sin_permiso'; end if;
  delete from rh_huellas where empleado_id = p_empleado;
  delete from rh_rostros where empleado_id = p_empleado;
  update rh_dispositivos set activo = false where empleado_id = p_empleado;
  update rh_codigos set expira_at = now() where empleado_id = p_empleado and usado_at is null;
  update rh_empleados set activo = false, baja_at = now(), huellas = 0, rostros = 0,
         movil_vinculado = false where id = p_empleado;
end $$;

-- ---------------------------------------------------------------------
-- Kiosco
-- ---------------------------------------------------------------------

-- Ahora baja también a quien solo tiene rostro, sus vectores, y el modo de
-- la sede.
create or replace function public.rh_kiosco_sync(p_id uuid, p_secreto text, p_desde timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d rh_dispositivos; ahora timestamptz := now();
begin
  d := _rh_equipo(p_id, p_secreto);
  if d.tipo <> 'kiosco' then raise exception 'equipo_invalido'; end if;

  return jsonb_build_object(
    'servidor_ts', ahora,
    'equipo', jsonb_build_object('id', d.id, 'nombre', d.nombre),
    'sede', (select to_jsonb(s) - 'creado_at' from rh_sedes s where s.id = d.sede_id),
    'activos', coalesce((select jsonb_agg(id) from rh_empleados
                          where activo and (huellas > 0 or rostros > 0)), '[]'),
    'empleados', coalesce((
      select jsonb_agg(_rh_empleado_json(e, true) || jsonb_build_object(
               'plantillas', coalesce((select jsonb_agg(jsonb_build_object(
                    'dedo', h.dedo, 'formato', h.formato, 'plantilla', h.plantilla))
                  from rh_huellas h where h.empleado_id = e.id), '[]'),
               'rostros', coalesce((select jsonb_agg(jsonb_build_object(
                    'modelo', r.modelo, 'vector', to_jsonb(r.vector)))
                  from rh_rostros r where r.empleado_id = e.id), '[]')))
        from rh_empleados e
       where e.activo and (e.huellas > 0 or e.rostros > 0)
         and (p_desde is null or e.actualizado_at > p_desde - interval '1 minute')
    ), '[]')
  );
end $$;

-- Registro biométrico en el kiosco: huellas y/o rostro con el mismo código.
--   p_plantillas = [{"dedo":2,"formato":"zk10","plantilla":"<b64>","calidad":80}, …]
--   p_rostros    = [{"modelo":"mobilefacenet-192","vector":[…192 números…],"calidad":90}, …]
-- Si llegan rostros, reemplazan a los anteriores del mismo modelo.
create or replace function public.rh_kiosco_enrolar(
  p_id uuid, p_secreto text, p_codigo text,
  p_plantillas jsonb default '[]', p_rostros jsonb default '[]')
returns jsonb language plpgsql security definer set search_path = public as $$
declare d rh_dispositivos; k rh_codigos; x jsonb; n int; nr int; modelos text[];
begin
  d := _rh_equipo(p_id, p_secreto);
  if d.tipo <> 'kiosco' then raise exception 'equipo_invalido'; end if;
  select * into k from rh_codigos
   where codigo = upper(trim(p_codigo)) and proposito = 'huella'
     and usado_at is null and expira_at > now()
   for update;
  if not found then raise exception 'codigo_invalido'; end if;

  p_plantillas := coalesce(p_plantillas, '[]');
  p_rostros := coalesce(p_rostros, '[]');
  if jsonb_typeof(p_plantillas) <> 'array' or jsonb_typeof(p_rostros) <> 'array'
     or jsonb_array_length(p_plantillas) + jsonb_array_length(p_rostros) = 0 then
    raise exception 'sin_plantillas';
  end if;

  for x in select * from jsonb_array_elements(p_plantillas) loop
    insert into rh_huellas (empleado_id, dedo, formato, plantilla, calidad, dispositivo_id)
    values (k.empleado_id, (x->>'dedo')::smallint, x->>'formato', x->>'plantilla',
            (x->>'calidad')::int, d.id)
    on conflict (empleado_id, dedo, formato) do update
      set plantilla = excluded.plantilla, calidad = excluded.calidad,
          dispositivo_id = excluded.dispositivo_id, creado_at = now();
  end loop;

  if jsonb_array_length(p_rostros) > 0 then
    select array_agg(distinct v->>'modelo') into modelos from jsonb_array_elements(p_rostros) v;
    delete from rh_rostros where empleado_id = k.empleado_id and modelo = any(modelos);
    for x in select * from jsonb_array_elements(p_rostros) loop
      insert into rh_rostros (empleado_id, modelo, vector, calidad, dispositivo_id)
      values (k.empleado_id, x->>'modelo',
              (select array_agg(value::real) from jsonb_array_elements_text(x->'vector')),
              (x->>'calidad')::int, d.id);
    end loop;
  end if;

  select count(*) into n from rh_huellas where empleado_id = k.empleado_id;
  select count(distinct modelo) into nr from rh_rostros where empleado_id = k.empleado_id;
  update rh_empleados set huellas = n, rostros = nr where id = k.empleado_id;
  update rh_codigos set usado_at = now(), usado_por = d.id where codigo = k.codigo;

  return jsonb_build_object('empleado_id', k.empleado_id, 'huellas', n, 'rostros', nr);
end $$;

-- La firma vieja (4 parámetros) choca con la nueva al llamarla por nombre.
drop function if exists public.rh_kiosco_enrolar(uuid, text, text, jsonb);

-- El código de huella sirve para "registro biométrico" (cara y/o dedo);
-- el kiosco necesita saber qué tiene ya registrado.
create or replace function public.rh_kiosco_codigo(p_id uuid, p_secreto text, p_codigo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d rh_dispositivos; k rh_codigos; e rh_empleados;
begin
  d := _rh_equipo(p_id, p_secreto);
  select * into k from rh_codigos
   where codigo = upper(trim(p_codigo)) and proposito = 'huella'
     and usado_at is null and expira_at > now();
  if not found then raise exception 'codigo_invalido'; end if;
  select * into e from rh_empleados where id = k.empleado_id and activo;
  if not found then raise exception 'empleado_no_disponible'; end if;
  return _rh_empleado_json(e, true) || jsonb_build_object('huellas', e.huellas, 'rostros', e.rostros);
end $$;

-- rh_checar: el kiosco dice con qué identificó (lector / rostro / rostro+huella).
-- Solo cambia la línea del método; el resto es idéntico a 001.
create or replace function public.rh_checar(p_id uuid, p_secreto text, p_checadas jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  d rh_dispositivos; x jsonb; e rh_empleados; t rh_turnos;
  v_emp uuid; v_ts timestamptz; v_lat float8; v_lng float8; v_prec float8;
  v_sim boolean; v_cid uuid; v_tipo text; v_estado text; v_sede uuid; v_sede_nombre text;
  v_dist float8; v_radio int; v_dentro boolean; v_ret int; v_min int; v_metodo text;
  ultima rh_checadas; existente rh_checadas; v_id uuid;
  resultados jsonb := '[]';
begin
  d := _rh_equipo(p_id, p_secreto);

  for x in
    select value from jsonb_array_elements(p_checadas) order by (value->>'ts')::timestamptz
  loop
    v_cid := (x->>'cliente_id')::uuid;

    select * into existente from rh_checadas where cliente_id = v_cid;
    if found then
      resultados := resultados || jsonb_build_object('cliente_id', v_cid, 'id', existente.id,
        'tipo', existente.tipo, 'estado', existente.estado, 'ts', existente.ts,
        'distancia_m', existente.distancia_m, 'minutos_retardo', existente.minutos_retardo,
        'repetida', true);
      continue;
    end if;

    v_emp := case when d.tipo = 'movil' then d.empleado_id else (x->>'empleado_id')::uuid end;
    select * into e from rh_empleados where id = v_emp and activo;
    if not found then
      resultados := resultados || jsonb_build_object('cliente_id', v_cid, 'error', 'empleado_no_disponible');
      continue;
    end if;

    v_metodo := case
      when d.tipo = 'movil' then 'biometria_movil'
      when x->>'metodo' in ('lector','rostro','rostro+huella') then x->>'metodo'
      else 'lector' end;

    v_ts   := least((x->>'ts')::timestamptz, now() + interval '2 minutes');
    v_lat  := (x->>'lat')::float8;
    v_lng  := (x->>'lng')::float8;
    v_prec := (x->>'precision_m')::float8;
    v_sim  := coalesce((x->>'gps_simulado')::boolean, false);

    select * into ultima from rh_checadas
     where empleado_id = e.id and estado <> 'anulada' and ts <= v_ts
     order by ts desc limit 1;
    if found and v_ts - ultima.ts < interval '60 seconds' then
      resultados := resultados || jsonb_build_object('cliente_id', v_cid, 'id', ultima.id,
        'tipo', ultima.tipo, 'estado', ultima.estado, 'ts', ultima.ts,
        'distancia_m', ultima.distancia_m, 'minutos_retardo', ultima.minutos_retardo,
        'repetida', true);
      continue;
    end if;

    select * into ultima from rh_checadas
     where empleado_id = e.id and estado = 'valida' and ts < v_ts
       and (ts at time zone 'America/Mexico_City')::date = (v_ts at time zone 'America/Mexico_City')::date
     order by ts desc limit 1;
    v_tipo := case when found and ultima.tipo = 'entrada' then 'salida' else 'entrada' end;

    v_sede := null; v_sede_nombre := null; v_dist := null; v_radio := null; v_dentro := null;
    if v_lat is not null and v_lng is not null then
      select s.id, s.nombre, _rh_distancia(v_lat, v_lng, s.lat, s.lng), s.radio_m
        into v_sede, v_sede_nombre, v_dist, v_radio
        from rh_sedes s where s.activa
       order by _rh_distancia(v_lat, v_lng, s.lat, s.lng) limit 1;
      if v_sede is not null then
        v_dentro := v_dist - least(coalesce(v_prec, 0), 50) <= v_radio;
      end if;
    end if;

    if d.tipo = 'kiosco' then
      if v_sede is null or v_dentro is null then
        v_sede := d.sede_id;
        select nombre into v_sede_nombre from rh_sedes where id = d.sede_id;
      end if;
      v_estado := case when v_dentro = false then 'revisar' else 'valida' end;
    else
      v_estado := case
        when v_lat is null then 'revisar'
        when v_sim then 'revisar'
        when v_dentro is distinct from true then 'fuera_geocerca'
        else 'valida' end;
    end if;

    v_ret := null;
    if v_tipo = 'entrada' and v_estado = 'valida' and e.turno_id is not null then
      select * into t from rh_turnos where id = e.turno_id;
      if found and extract(isodow from (v_ts at time zone 'America/Mexico_City'))::smallint = any(t.dias)
         and not exists (select 1 from rh_checadas where empleado_id = e.id and tipo = 'entrada'
                           and estado = 'valida'
                           and (ts at time zone 'America/Mexico_City')::date
                               = (v_ts at time zone 'America/Mexico_City')::date) then
        v_min := floor(extract(epoch from ((v_ts at time zone 'America/Mexico_City')::time - t.hora_entrada)) / 60);
        if v_min > t.tolerancia_min then v_ret := v_min; end if;
      end if;
    end if;

    insert into rh_checadas (cliente_id, empleado_id, dispositivo_id, tipo, metodo, ts,
       lat, lng, precision_m, gps_simulado, sede_id, distancia_m, dentro_geocerca,
       puntaje, minutos_retardo, estado)
    values (v_cid, e.id, d.id, v_tipo, v_metodo,
       v_ts, v_lat, v_lng, v_prec, v_sim, v_sede, round(v_dist), v_dentro,
       (x->>'puntaje')::int, v_ret, v_estado)
    returning id into v_id;

    resultados := resultados || jsonb_build_object('cliente_id', v_cid, 'id', v_id,
      'empleado_id', e.id, 'tipo', v_tipo, 'estado', v_estado, 'ts', v_ts,
      'sede', v_sede_nombre, 'distancia_m', round(v_dist), 'radio_m', v_radio,
      'minutos_retardo', v_ret, 'repetida', false);
  end loop;

  return jsonb_build_object('servidor_ts', now(), 'resultados', resultados);
end $$;

-- ---------------------------------------------------------------------
-- Permisos de las funciones nuevas / reemplazadas
-- ---------------------------------------------------------------------
revoke execute on function public.rh_borrar_rostros(uuid) from public, anon, authenticated;
revoke execute on function public.rh_dar_baja(uuid) from public, anon, authenticated;
revoke execute on function public.rh_kiosco_sync(uuid, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.rh_kiosco_enrolar(uuid, text, text, jsonb, jsonb) from public, anon, authenticated;
revoke execute on function public.rh_kiosco_codigo(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.rh_checar(uuid, text, jsonb) from public, anon, authenticated;

grant execute on function public.rh_borrar_rostros(uuid) to authenticated;
grant execute on function public.rh_dar_baja(uuid) to authenticated;
grant execute on function public.rh_kiosco_sync(uuid, text, timestamptz) to anon, authenticated;
grant execute on function public.rh_kiosco_enrolar(uuid, text, text, jsonb, jsonb) to anon, authenticated;
grant execute on function public.rh_kiosco_codigo(uuid, text, text) to anon, authenticated;
grant execute on function public.rh_checar(uuid, text, jsonb) to anon, authenticated;

-- PostgREST guarda en caché las firmas de las funciones: que las relea ya.
notify pgrst, 'reload schema';
