-- =====================================================================
--  001_reloj_checador.sql  —  Reloj checador Arypsa (app RH + app checador)
--
--  Correr UNA vez en el SQL Editor del proyecto de Supabase del checador.
--  Recomendado: un proyecto de Supabase APARTE del portal (p. ej. "arypsa-rh").
--  Las apps llevan la llave anon dentro del APK; en un proyecto aparte, una
--  tabla del portal sin RLS nunca queda expuesta por accidente, y las
--  plantillas de huella (dato biométrico) viven separadas de todo lo demás.
--
--  Modelo de seguridad
--  -------------------
--  * Usuarios de RH: Supabase Auth (correo + contraseña) + fila en rh_perfiles.
--    Ven y editan todo por RLS, EXCEPTO las plantillas de huella.
--  * Equipos (kiosco / celular): NO son usuarios. Hablan con la llave anon y
--    SOLO pueden llamar las funciones rh_activar / rh_kiosco_* / rh_movil_* /
--    rh_checar, que validan su id + secreto. anon no puede leer ninguna tabla.
--  * El secreto del equipo se guarda solo como hash sha256.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- Catálogos
-- ---------------------------------------------------------------------
create table if not exists public.rh_sedes (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null,
  direccion   text,
  lat         double precision not null check (lat between -90 and 90),
  lng         double precision not null check (lng between -180 and 180),
  radio_m     integer not null default 150 check (radio_m between 30 and 5000),
  activa      boolean not null default true,
  creado_at   timestamptz not null default now()
);

create table if not exists public.rh_turnos (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  hora_entrada    time not null,
  hora_salida     time not null,
  tolerancia_min  integer not null default 10 check (tolerancia_min between 0 and 120),
  -- Días ISO: 1 = lunes … 7 = domingo
  dias            smallint[] not null default '{1,2,3,4,5}',
  activo          boolean not null default true,
  creado_at       timestamptz not null default now()
);

create table if not exists public.rh_empleados (
  id                 uuid primary key default gen_random_uuid(),
  numero             text not null unique,
  nombres            text not null,
  apellidos          text not null default '',
  puesto             text,
  departamento       text,
  sede_id            uuid references public.rh_sedes(id),
  turno_id           uuid references public.rh_turnos(id),
  tipo               text not null default 'planta' check (tipo in ('planta','administrativo')),
  checa_movil        boolean not null default false,
  telefono           text,
  correo             text,
  fecha_ingreso      date,
  -- Foto chica (JPEG ~480px) en base64. Así el kiosco la baja junto con la
  -- huella y la muestra sin internet, sin políticas de Storage.
  foto               text,
  -- Consentimiento expreso para tratar datos biométricos (LFPDPPP art. 9).
  consentimiento_at  timestamptz,
  consentimiento_por uuid,
  -- Contadores que mantienen las funciones (RH no puede leer rh_huellas).
  huellas            integer not null default 0,
  movil_vinculado    boolean not null default false,
  activo             boolean not null default true,
  baja_at            timestamptz,
  creado_at          timestamptz not null default now(),
  actualizado_at     timestamptz not null default now()
);

create table if not exists public.rh_huellas (
  id              uuid primary key default gen_random_uuid(),
  empleado_id     uuid not null references public.rh_empleados(id) on delete cascade,
  dedo            smallint not null check (dedo between 1 and 10),
  formato         text not null,         -- 'zk10', 'sgfp', 'sim' …
  plantilla       text not null,         -- base64 tal como la entrega el SDK
  calidad         integer,
  dispositivo_id  uuid,
  creado_at       timestamptz not null default now(),
  unique (empleado_id, dedo, formato)
);

create table if not exists public.rh_dispositivos (
  id               uuid primary key default gen_random_uuid(),
  tipo             text not null check (tipo in ('kiosco','movil')),
  nombre           text not null,
  empleado_id      uuid references public.rh_empleados(id),
  sede_id          uuid references public.rh_sedes(id),
  secreto_hash     text not null,
  plataforma       text,
  modelo           text,
  app_version      text,
  activo           boolean not null default true,
  creado_at        timestamptz not null default now(),
  ultimo_contacto  timestamptz,
  check ((tipo = 'kiosco' and sede_id is not null) or (tipo = 'movil' and empleado_id is not null))
);
-- Un solo celular activo por empleado.
create unique index if not exists rh_dispositivos_un_movil
  on public.rh_dispositivos (empleado_id) where tipo = 'movil' and activo;

create table if not exists public.rh_codigos (
  codigo        text primary key,
  proposito     text not null check (proposito in ('huella','movil','kiosco')),
  empleado_id   uuid references public.rh_empleados(id) on delete cascade,
  sede_id       uuid references public.rh_sedes(id),
  nombre_equipo text,
  expira_at     timestamptz not null,
  usado_at      timestamptz,
  usado_por     uuid,
  creado_por    uuid,
  creado_at     timestamptz not null default now()
);

create table if not exists public.rh_checadas (
  id               uuid primary key default gen_random_uuid(),
  cliente_id       uuid not null unique,   -- generado en el equipo: reintentos sin duplicar
  empleado_id      uuid not null references public.rh_empleados(id),
  dispositivo_id   uuid references public.rh_dispositivos(id),
  tipo             text not null check (tipo in ('entrada','salida')),
  metodo           text not null check (metodo in ('lector','biometria_movil')),
  ts               timestamptz not null,   -- hora del equipo al checar
  recibido_at      timestamptz not null default now(),
  lat              double precision,
  lng              double precision,
  precision_m      double precision,
  gps_simulado     boolean not null default false,
  sede_id          uuid references public.rh_sedes(id),
  distancia_m      integer,
  dentro_geocerca  boolean,
  puntaje          integer,
  minutos_retardo  integer,
  estado           text not null default 'valida'
                   check (estado in ('valida','fuera_geocerca','revisar','anulada')),
  nota             text
);
create index if not exists rh_checadas_emp_ts on public.rh_checadas (empleado_id, ts desc);
create index if not exists rh_checadas_ts on public.rh_checadas (ts desc);

create table if not exists public.rh_perfiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  nombre     text not null,
  rol        text not null default 'rh' check (rol in ('rh','admin')),
  activo     boolean not null default true,
  creado_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------
create or replace function public.rh_es_rh() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from rh_perfiles where user_id = auth.uid() and activo);
$$;

create or replace function public._rh_hash(p text) returns text
language sql immutable set search_path = public, extensions as $$
  select encode(extensions.digest(coalesce(p,''), 'sha256'), 'hex');
$$;

-- Distancia en metros (haversine).
create or replace function public._rh_distancia(lat1 float8, lng1 float8, lat2 float8, lng2 float8)
returns float8 language sql immutable as $$
  select 2 * 6371000 * asin(sqrt(
      power(sin(radians(lat2 - lat1) / 2), 2) +
      cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- Código legible: sin 0/O ni 1/I/L.
create or replace function public._rh_nuevo_codigo() returns text
language plpgsql volatile set search_path = public, extensions as $$
declare
  alfabeto constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  b bytea := extensions.gen_random_bytes(8);
  r text := '';
begin
  for i in 0..7 loop
    r := r || substr(alfabeto, (get_byte(b, i) % length(alfabeto)) + 1, 1);
  end loop;
  return r;
end $$;

-- Valida id + secreto del equipo. Lanza 'equipo_invalido' si no cuadra.
create or replace function public._rh_equipo(p_id uuid, p_secreto text)
returns public.rh_dispositivos
language plpgsql security definer set search_path = public as $$
declare d rh_dispositivos;
begin
  select * into d from rh_dispositivos
   where id = p_id and activo and secreto_hash = _rh_hash(p_secreto);
  if not found then
    raise exception 'equipo_invalido' using errcode = 'P0001';
  end if;
  update rh_dispositivos set ultimo_contacto = now() where id = p_id;
  return d;
end $$;

create or replace function public._rh_empleado_json(e public.rh_empleados, con_foto boolean)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'numero', e.numero, 'nombres', e.nombres, 'apellidos', e.apellidos,
    'puesto', e.puesto, 'departamento', e.departamento, 'tipo', e.tipo,
    'sede_id', e.sede_id, 'foto', case when con_foto then e.foto end,
    'turno', (select jsonb_build_object('nombre', t.nombre,
                 'entrada', to_char(t.hora_entrada, 'HH24:MI'),
                 'salida',  to_char(t.hora_salida,  'HH24:MI'),
                 'tolerancia_min', t.tolerancia_min, 'dias', to_jsonb(t.dias))
              from rh_turnos t where t.id = e.turno_id)
  );
$$;

create or replace function public._rh_touch() returns trigger
language plpgsql as $$
begin new.actualizado_at := now(); return new; end $$;

drop trigger if exists rh_empleados_touch on public.rh_empleados;
create trigger rh_empleados_touch before update on public.rh_empleados
  for each row execute function public._rh_touch();

-- ---------------------------------------------------------------------
-- Funciones para RH (usuario autenticado con perfil)
-- ---------------------------------------------------------------------

-- Genera un código de un solo uso.
--   'huella' : registrar huella de p_empleado en un kiosco      (vence en 24 h)
--   'movil'  : vincular el celular de p_empleado                (vence en 24 h)
--   'kiosco' : dar de alta un kiosco nuevo en p_sede            (vence en 2 h)
create or replace function public.rh_generar_codigo(
  p_proposito text, p_empleado uuid default null, p_sede uuid default null,
  p_nombre text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c text; vence timestamptz; e rh_empleados;
begin
  if not rh_es_rh() then raise exception 'sin_permiso'; end if;

  if p_proposito in ('huella','movil') then
    select * into e from rh_empleados where id = p_empleado and activo;
    if not found then raise exception 'empleado_no_encontrado'; end if;
    if e.consentimiento_at is null then raise exception 'falta_consentimiento'; end if;
    if p_proposito = 'movil' and not e.checa_movil then
      raise exception 'empleado_sin_checado_movil';
    end if;
    vence := now() + interval '24 hours';
  elsif p_proposito = 'kiosco' then
    if p_sede is null or not exists (select 1 from rh_sedes where id = p_sede and activa) then
      raise exception 'sede_no_encontrada';
    end if;
    vence := now() + interval '2 hours';
  else
    raise exception 'proposito_invalido';
  end if;

  -- Un código vivo por empleado y propósito: el anterior deja de servir.
  update rh_codigos set expira_at = now()
   where usado_at is null and expira_at > now() and proposito = p_proposito
     and empleado_id is not distinct from p_empleado and p_proposito <> 'kiosco';

  loop
    c := _rh_nuevo_codigo();
    exit when not exists (select 1 from rh_codigos where codigo = c);
  end loop;

  insert into rh_codigos (codigo, proposito, empleado_id, sede_id, nombre_equipo, expira_at, creado_por)
  values (c, p_proposito, p_empleado, p_sede, nullif(trim(p_nombre), ''), vence, auth.uid());

  return jsonb_build_object('codigo', c, 'expira_at', vence, 'proposito', p_proposito);
end $$;

create or replace function public.rh_borrar_huellas(p_empleado uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not rh_es_rh() then raise exception 'sin_permiso'; end if;
  delete from rh_huellas where empleado_id = p_empleado;
  update rh_empleados set huellas = 0 where id = p_empleado;
end $$;

create or replace function public.rh_desactivar_equipo(p_equipo uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d rh_dispositivos;
begin
  if not rh_es_rh() then raise exception 'sin_permiso'; end if;
  update rh_dispositivos set activo = false where id = p_equipo returning * into d;
  if d.tipo = 'movil' then
    update rh_empleados set movil_vinculado = false where id = d.empleado_id;
  end if;
end $$;

-- Baja: se desactiva, se borran huellas y se cortan sus equipos. Las checadas
-- se conservan (son registro laboral).
create or replace function public.rh_dar_baja(p_empleado uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not rh_es_rh() then raise exception 'sin_permiso'; end if;
  delete from rh_huellas where empleado_id = p_empleado;
  update rh_dispositivos set activo = false where empleado_id = p_empleado;
  update rh_codigos set expira_at = now() where empleado_id = p_empleado and usado_at is null;
  update rh_empleados set activo = false, baja_at = now(), huellas = 0,
         movil_vinculado = false where id = p_empleado;
end $$;

-- Resumen de un día: una fila por empleado activo.
create or replace function public.rh_resumen_dia(p_fecha date)
returns table (
  empleado_id uuid, numero text, nombre text, puesto text, tipo text, foto text,
  entrada timestamptz, salida timestamptz, minutos_retardo integer,
  checadas integer, alertas integer, ultima_sede text, labora_hoy boolean)
language sql stable security definer set search_path = public as $$
  with dia as (
    select c.* from rh_checadas c
     where (c.ts at time zone 'America/Mexico_City')::date = p_fecha
       and c.estado <> 'anulada'
  )
  select e.id, e.numero, trim(e.nombres || ' ' || e.apellidos), e.puesto, e.tipo, e.foto,
         (select min(ts) from dia where dia.empleado_id = e.id and tipo = 'entrada' and estado = 'valida'),
         (select max(ts) from dia where dia.empleado_id = e.id and tipo = 'salida'  and estado = 'valida'),
         (select minutos_retardo from dia where dia.empleado_id = e.id and tipo = 'entrada'
            and estado = 'valida' order by ts limit 1),
         (select count(*)::int from dia where dia.empleado_id = e.id),
         (select count(*)::int from dia where dia.empleado_id = e.id and estado <> 'valida'),
         (select s.nombre from dia join rh_sedes s on s.id = dia.sede_id
           where dia.empleado_id = e.id order by ts desc limit 1),
         coalesce((select extract(isodow from p_fecha)::smallint = any(t.dias)
                     from rh_turnos t where t.id = e.turno_id), true)
    from rh_empleados e
   where e.activo and rh_es_rh()
   order by e.nombres, e.apellidos;
$$;

-- ---------------------------------------------------------------------
-- Funciones para los equipos (llave anon + id/secreto)
-- ---------------------------------------------------------------------

-- Canjea un código 'kiosco' o 'movil'. Devuelve el secreto UNA sola vez.
create or replace function public.rh_activar(p_codigo text, p_info jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  k rh_codigos; e rh_empleados; s rh_sedes; secreto text; nuevo uuid;
begin
  select * into k from rh_codigos
   where codigo = upper(trim(p_codigo)) and usado_at is null and expira_at > now()
   for update;
  if not found then raise exception 'codigo_invalido'; end if;
  if k.proposito not in ('kiosco','movil') then raise exception 'codigo_no_es_de_equipo'; end if;

  secreto := encode(gen_random_bytes(32), 'hex');

  if k.proposito = 'movil' then
    select * into e from rh_empleados where id = k.empleado_id and activo and checa_movil;
    if not found then raise exception 'empleado_no_disponible'; end if;
    -- El celular anterior (si había) deja de servir.
    update rh_dispositivos set activo = false where empleado_id = e.id and tipo = 'movil' and activo;
    insert into rh_dispositivos (tipo, nombre, empleado_id, sede_id, secreto_hash, plataforma, modelo, app_version)
    values ('movil', coalesce(p_info->>'modelo', 'Celular') || ' · ' || e.nombres, e.id, e.sede_id,
            _rh_hash(secreto), p_info->>'plataforma', p_info->>'modelo', p_info->>'version')
    returning id into nuevo;
    update rh_empleados set movil_vinculado = true where id = e.id;
  else
    select * into s from rh_sedes where id = k.sede_id;
    insert into rh_dispositivos (tipo, nombre, sede_id, secreto_hash, plataforma, modelo, app_version)
    values ('kiosco', coalesce(k.nombre_equipo, 'Kiosco ' || s.nombre), k.sede_id,
            _rh_hash(secreto), p_info->>'plataforma', p_info->>'modelo', p_info->>'version')
    returning id into nuevo;
  end if;

  update rh_codigos set usado_at = now(), usado_por = nuevo where codigo = k.codigo;

  return jsonb_build_object('equipo_id', nuevo, 'secreto', secreto, 'tipo', k.proposito);
end $$;

-- Kiosco: catálogo de empleados con plantillas. Incremental con p_desde.
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
    'activos', coalesce((select jsonb_agg(id) from rh_empleados where activo and huellas > 0), '[]'),
    'empleados', coalesce((
      select jsonb_agg(_rh_empleado_json(e, true) || jsonb_build_object(
               'plantillas', coalesce((select jsonb_agg(jsonb_build_object(
                    'dedo', h.dedo, 'formato', h.formato, 'plantilla', h.plantilla))
                  from rh_huellas h where h.empleado_id = e.id), '[]')))
        from rh_empleados e
       where e.activo and e.huellas > 0
         and (p_desde is null or e.actualizado_at > p_desde - interval '1 minute')
    ), '[]')
  );
end $$;

-- Kiosco: a quién pertenece un código de huella (para mostrar nombre y foto
-- antes de capturar).
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
  return _rh_empleado_json(e, true) || jsonb_build_object('huellas', e.huellas);
end $$;

-- Kiosco: guarda las plantillas capturadas.
--   p_plantillas = [{"dedo":2,"formato":"zk10","plantilla":"<b64>","calidad":80}, …]
create or replace function public.rh_kiosco_enrolar(p_id uuid, p_secreto text, p_codigo text, p_plantillas jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d rh_dispositivos; k rh_codigos; x jsonb; n int;
begin
  d := _rh_equipo(p_id, p_secreto);
  if d.tipo <> 'kiosco' then raise exception 'equipo_invalido'; end if;
  select * into k from rh_codigos
   where codigo = upper(trim(p_codigo)) and proposito = 'huella'
     and usado_at is null and expira_at > now()
   for update;
  if not found then raise exception 'codigo_invalido'; end if;
  if jsonb_typeof(p_plantillas) <> 'array' or jsonb_array_length(p_plantillas) = 0 then
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

  select count(*) into n from rh_huellas where empleado_id = k.empleado_id;
  update rh_empleados set huellas = n where id = k.empleado_id;  -- también mueve actualizado_at
  update rh_codigos set usado_at = now(), usado_por = d.id where codigo = k.codigo;

  return jsonb_build_object('empleado_id', k.empleado_id, 'huellas', n);
end $$;

-- Celular: quién soy, sedes válidas y mis checadas de hoy.
create or replace function public.rh_movil_estado(p_id uuid, p_secreto text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d rh_dispositivos; e rh_empleados; hoy date := (now() at time zone 'America/Mexico_City')::date;
begin
  d := _rh_equipo(p_id, p_secreto);
  if d.tipo <> 'movil' then raise exception 'equipo_invalido'; end if;
  select * into e from rh_empleados where id = d.empleado_id and activo;
  if not found then raise exception 'equipo_invalido'; end if;
  return jsonb_build_object(
    'servidor_ts', now(),
    'empleado', _rh_empleado_json(e, true),
    'sedes', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre,
                 'lat', lat, 'lng', lng, 'radio_m', radio_m)) from rh_sedes where activa), '[]'),
    'hoy', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'tipo', c.tipo, 'ts', c.ts,
                 'estado', c.estado, 'sede', s.nombre, 'distancia_m', c.distancia_m,
                 'minutos_retardo', c.minutos_retardo) order by c.ts)
               from rh_checadas c left join rh_sedes s on s.id = c.sede_id
              where c.empleado_id = e.id
                and (c.ts at time zone 'America/Mexico_City')::date = hoy), '[]')
  );
end $$;

-- Registra checadas (una o un lote que se quedó guardado sin red).
--   p_checadas = [{"cliente_id":"uuid","empleado_id":"uuid (solo kiosco)",
--                  "ts":"2026-10-13T07:58:00-06:00","lat":21.1,"lng":-101.6,
--                  "precision_m":12,"gps_simulado":false,"puntaje":87}, …]
-- El servidor decide entrada/salida, sede, geocerca y retardo.
create or replace function public.rh_checar(p_id uuid, p_secreto text, p_checadas jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  d rh_dispositivos; x jsonb; e rh_empleados; t rh_turnos;
  v_emp uuid; v_ts timestamptz; v_lat float8; v_lng float8; v_prec float8;
  v_sim boolean; v_cid uuid; v_tipo text; v_estado text; v_sede uuid; v_sede_nombre text;
  v_dist float8; v_radio int; v_dentro boolean; v_ret int; v_min int;
  ultima rh_checadas; existente rh_checadas; v_id uuid;
  resultados jsonb := '[]';
begin
  d := _rh_equipo(p_id, p_secreto);

  for x in
    select value from jsonb_array_elements(p_checadas) order by (value->>'ts')::timestamptz
  loop
    v_cid := (x->>'cliente_id')::uuid;

    -- Reintento de algo que ya llegó: se devuelve lo que se guardó.
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

    v_ts   := least((x->>'ts')::timestamptz, now() + interval '2 minutes');
    v_lat  := (x->>'lat')::float8;
    v_lng  := (x->>'lng')::float8;
    v_prec := (x->>'precision_m')::float8;
    v_sim  := coalesce((x->>'gps_simulado')::boolean, false);

    -- Doble checada en menos de 60 s: se toma como la misma.
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

    -- Entrada/salida alterna dentro del mismo día (hora de México), contando
    -- solo checadas válidas.
    select * into ultima from rh_checadas
     where empleado_id = e.id and estado = 'valida' and ts < v_ts
       and (ts at time zone 'America/Mexico_City')::date = (v_ts at time zone 'America/Mexico_City')::date
     order by ts desc limit 1;
    v_tipo := case when found and ultima.tipo = 'entrada' then 'salida' else 'entrada' end;

    -- Geocerca: la sede activa más cercana.
    v_sede := null; v_sede_nombre := null; v_dist := null; v_radio := null; v_dentro := null;
    if v_lat is not null and v_lng is not null then
      select s.id, s.nombre, _rh_distancia(v_lat, v_lng, s.lat, s.lng), s.radio_m
        into v_sede, v_sede_nombre, v_dist, v_radio
        from rh_sedes s where s.activa
       order by _rh_distancia(v_lat, v_lng, s.lat, s.lng) limit 1;
      if v_sede is not null then
        -- Se perdona hasta 50 m del margen de error que reporta el GPS.
        v_dentro := v_dist - least(coalesce(v_prec, 0), 50) <= v_radio;
      end if;
    end if;

    if d.tipo = 'kiosco' then
      -- El kiosco está atornillado en su sede; sin GPS se le cree.
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

    -- Retardo contra el turno, solo en la primera entrada válida del día.
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
    values (v_cid, e.id, d.id, v_tipo,
       case when d.tipo = 'kiosco' then 'lector' else 'biometria_movil' end,
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
-- RLS y permisos
-- ---------------------------------------------------------------------
alter table public.rh_sedes        enable row level security;
alter table public.rh_turnos       enable row level security;
alter table public.rh_empleados    enable row level security;
alter table public.rh_huellas      enable row level security;
alter table public.rh_dispositivos enable row level security;
alter table public.rh_codigos      enable row level security;
alter table public.rh_checadas     enable row level security;
alter table public.rh_perfiles     enable row level security;

revoke all on public.rh_sedes, public.rh_turnos, public.rh_empleados, public.rh_huellas,
              public.rh_dispositivos, public.rh_codigos, public.rh_checadas, public.rh_perfiles
  from anon, authenticated;

grant select, insert, update on public.rh_sedes, public.rh_turnos, public.rh_empleados to authenticated;
grant select, update (activo, nombre) on public.rh_dispositivos to authenticated;
grant select on public.rh_codigos to authenticated;
grant select, update (estado, nota) on public.rh_checadas to authenticated;
grant select on public.rh_perfiles to authenticated;
-- rh_huellas: ningún grant. Solo las funciones security definer la tocan.

drop policy if exists rh_sedes_rh on public.rh_sedes;
create policy rh_sedes_rh on public.rh_sedes for all to authenticated
  using (rh_es_rh()) with check (rh_es_rh());
drop policy if exists rh_turnos_rh on public.rh_turnos;
create policy rh_turnos_rh on public.rh_turnos for all to authenticated
  using (rh_es_rh()) with check (rh_es_rh());
drop policy if exists rh_empleados_rh on public.rh_empleados;
create policy rh_empleados_rh on public.rh_empleados for all to authenticated
  using (rh_es_rh()) with check (rh_es_rh());
drop policy if exists rh_dispositivos_rh on public.rh_dispositivos;
create policy rh_dispositivos_rh on public.rh_dispositivos for all to authenticated
  using (rh_es_rh()) with check (rh_es_rh());
drop policy if exists rh_codigos_rh on public.rh_codigos;
create policy rh_codigos_rh on public.rh_codigos for select to authenticated using (rh_es_rh());
drop policy if exists rh_checadas_rh on public.rh_checadas;
create policy rh_checadas_rh on public.rh_checadas for all to authenticated
  using (rh_es_rh()) with check (rh_es_rh());
drop policy if exists rh_perfiles_yo on public.rh_perfiles;
create policy rh_perfiles_yo on public.rh_perfiles for select to authenticated
  using (user_id = auth.uid());

-- Funciones: por defecto Postgres (y Supabase) dan EXECUTE a todos. Se quita
-- SOLO en las funciones rh_ de este script y se da a quien le toca.
do $$
declare f text;
begin
  for f in select p.oid::regprocedure::text from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname like '%rh\_%' escape '\'
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;
end $$;

grant execute on function public.rh_es_rh() to authenticated;
grant execute on function public.rh_generar_codigo(text, uuid, uuid, text) to authenticated;
grant execute on function public.rh_borrar_huellas(uuid) to authenticated;
grant execute on function public.rh_desactivar_equipo(uuid) to authenticated;
grant execute on function public.rh_dar_baja(uuid) to authenticated;
grant execute on function public.rh_resumen_dia(date) to authenticated;

grant execute on function public.rh_activar(text, jsonb) to anon, authenticated;
grant execute on function public.rh_kiosco_sync(uuid, text, timestamptz) to anon, authenticated;
grant execute on function public.rh_kiosco_codigo(uuid, text, text) to anon, authenticated;
grant execute on function public.rh_kiosco_enrolar(uuid, text, text, jsonb) to anon, authenticated;
grant execute on function public.rh_movil_estado(uuid, text) to anon, authenticated;
grant execute on function public.rh_checar(uuid, text, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Después de correr esto:
--   1. Authentication › Users › Add user: crear la cuenta de RH (correo + contraseña).
--   2. Darle perfil (cambiar el correo):
--        insert into rh_perfiles (user_id, nombre, rol)
--        select id, 'Recursos Humanos', 'admin' from auth.users where email = 'rh@arypsa.com';
--   3. Authentication › Sign In / Providers: apagar "Allow new users to sign up".
-- ---------------------------------------------------------------------
