-- =====================================================================
--  003_expediente.sql  —  Expediente completo del empleado
--
--  Correr DESPUÉS de 001 y 002, una sola vez, en el SQL Editor del
--  proyecto arypsa-rh. Se puede volver a correr sin romper nada.
--
--  Qué agrega
--  ----------
--  * rh_empleados: datos personales (CURP, RFC, NSS, nacimiento, domicilio),
--    fiscales (régimen, CP fiscal para el CFDI de nómina), IMSS / INFONAVIT /
--    FONACOT, contrato y salario, banco (CLABE), tallas de uniforme y EPP,
--    contactos de emergencia, beneficiarios (LFT art. 25 fr. X) y datos de
--    la baja (tipo, motivo, recontratable).
--  * rh_tipos_documento: catálogo editable de documentos del expediente
--    (cuáles son obligatorios y cuáles vencen).
--  * rh_documentos: los archivos subidos (van al bucket privado
--    "rh-expedientes" de Storage; aquí solo queda la ruta).
--  * rh_historial: cada cambio de puesto, salario, sede, turno, jefe,
--    contrato o estatus queda registrado con fecha y quién lo hizo.
--  * rh_baja_empleado(): baja con fecha, tipo y motivo.
--
--  Solo RH (rh_perfiles) puede leer o escribir todo esto. El kiosco y los
--  celulares NO ven ninguno de estos datos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Datos nuevos del empleado
-- ---------------------------------------------------------------------
alter table public.rh_empleados
  -- Nombre separado como lo pide el SAT en el CFDI de nómina
  add column if not exists apellido_paterno    text,
  add column if not exists apellido_materno    text,
  -- Personales
  add column if not exists curp                text,
  add column if not exists rfc                 text,
  add column if not exists fecha_nacimiento    date,
  add column if not exists sexo                text,
  add column if not exists estado_civil        text,
  add column if not exists nacionalidad        text default 'Mexicana',
  add column if not exists lugar_nacimiento    text,
  add column if not exists escolaridad         text,
  add column if not exists tipo_sangre         text,
  add column if not exists alergias            text,
  -- Contacto y domicilio
  add column if not exists telefono_casa       text,
  add column if not exists correo_empresa      text,
  add column if not exists calle               text,
  add column if not exists num_ext             text,
  add column if not exists num_int             text,
  add column if not exists colonia             text,
  add column if not exists municipio           text,
  add column if not exists estado              text,
  add column if not exists cp                  text,
  -- Fiscal (CFDI 4.0 de nómina: RFC, nombre, CP fiscal y régimen 605)
  add column if not exists regimen_fiscal      text default '605',
  add column if not exists cp_fiscal           text,
  -- Seguridad social
  add column if not exists nss                 text,
  add column if not exists umf                 text,
  add column if not exists fecha_alta_imss     date,
  add column if not exists registro_patronal   text,
  add column if not exists infonavit_credito   text,
  add column if not exists infonavit_tipo      text,
  add column if not exists infonavit_valor     numeric(12,4),
  add column if not exists fonacot_credito     text,
  -- Relación laboral
  add column if not exists jefe_id             uuid references public.rh_empleados(id) on delete set null,
  add column if not exists tipo_contrato       text default 'indeterminado',
  add column if not exists fecha_fin_contrato  date,
  add column if not exists fin_periodo_prueba  date,
  add column if not exists jornada             text default 'diurna',
  add column if not exists salario_diario      numeric(12,2),
  add column if not exists sdi                 numeric(12,2),
  add column if not exists periodicidad_pago   text default 'semanal',
  add column if not exists forma_pago          text default 'transferencia',
  -- Banco (dispersión de nómina)
  add column if not exists banco               text,
  add column if not exists clabe               text,
  add column if not exists cuenta              text,
  -- Uniforme y equipo de protección personal
  add column if not exists talla_camisa        text,
  add column if not exists talla_pantalon      text,
  add column if not exists talla_calzado       text,
  -- Listas: [{nombre, parentesco, telefono}] / [{nombre, parentesco, porcentaje}]
  add column if not exists contactos_emergencia jsonb not null default '[]',
  add column if not exists beneficiarios        jsonb not null default '[]',
  add column if not exists notas               text,
  -- Baja
  add column if not exists fecha_baja          date,
  add column if not exists tipo_baja           text,
  add column if not exists motivo_baja         text,
  add column if not exists recontratable       boolean;

-- Checks (se crean solo si no existen, para poder volver a correr el script)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'rh_empleados_sexo_chk') then
    alter table public.rh_empleados add constraint rh_empleados_sexo_chk
      check (sexo is null or sexo in ('H','M','X'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_empleados_curp_chk') then
    alter table public.rh_empleados add constraint rh_empleados_curp_chk
      check (curp is null or curp ~ '^[A-Z][AEIOUX][A-Z]{2}[0-9]{6}[HMX][A-Z]{5}[0-9A-Z][0-9]$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_empleados_rfc_chk') then
    alter table public.rh_empleados add constraint rh_empleados_rfc_chk
      check (rfc is null or rfc ~ '^[A-ZÑ&]{4}[0-9]{6}[A-Z0-9]{3}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_empleados_nss_chk') then
    alter table public.rh_empleados add constraint rh_empleados_nss_chk
      check (nss is null or nss ~ '^[0-9]{11}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_empleados_clabe_chk') then
    alter table public.rh_empleados add constraint rh_empleados_clabe_chk
      check (clabe is null or clabe ~ '^[0-9]{18}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_empleados_contrato_chk') then
    alter table public.rh_empleados add constraint rh_empleados_contrato_chk
      check (tipo_contrato is null or tipo_contrato in
        ('indeterminado','determinado','obra','prueba','capacitacion','temporada'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_empleados_jornada_chk') then
    alter table public.rh_empleados add constraint rh_empleados_jornada_chk
      check (jornada is null or jornada in ('diurna','nocturna','mixta'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_empleados_periodicidad_chk') then
    alter table public.rh_empleados add constraint rh_empleados_periodicidad_chk
      check (periodicidad_pago is null or periodicidad_pago in ('semanal','catorcenal','quincenal','mensual'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_empleados_infonavit_chk') then
    alter table public.rh_empleados add constraint rh_empleados_infonavit_chk
      check (infonavit_tipo is null or infonavit_tipo in ('porcentaje','cuota_fija','vsm','umi'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_empleados_baja_chk') then
    alter table public.rh_empleados add constraint rh_empleados_baja_chk
      check (tipo_baja is null or tipo_baja in
        ('renuncia','despido','termino_contrato','abandono','jubilacion','defuncion','otro'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_empleados_jefe_chk') then
    alter table public.rh_empleados add constraint rh_empleados_jefe_chk
      check (jefe_id is null or jefe_id <> id);
  end if;
end $$;

-- CURP, RFC y NSS no se repiten entre empleados ACTIVOS (un recontratado
-- puede tener un registro viejo dado de baja con los mismos datos).
create unique index if not exists rh_empleados_curp_uq on public.rh_empleados (curp) where activo and curp is not null;
create unique index if not exists rh_empleados_rfc_uq  on public.rh_empleados (rfc)  where activo and rfc  is not null;
create unique index if not exists rh_empleados_nss_uq  on public.rh_empleados (nss)  where activo and nss  is not null;
create index if not exists rh_empleados_jefe_idx on public.rh_empleados (jefe_id);

-- ---------------------------------------------------------------------
-- Catálogo de documentos del expediente
-- ---------------------------------------------------------------------
create table if not exists public.rh_tipos_documento (
  id           text primary key,
  nombre       text not null,
  descripcion  text,
  categoria    text not null default 'personal'
               check (categoria in ('personal','fiscal','imss','laboral','salud','capacitacion','baja')),
  obligatorio  boolean not null default false,
  -- Vence: el documento se pide con fecha de vencimiento (INE, DC-3...).
  vence        boolean not null default false,
  -- Antigüedad máxima aceptada al recibirlo (p. ej. comprobante de domicilio: 90 días).
  vigencia_dias integer,
  orden        integer not null default 100,
  activo       boolean not null default true
);

insert into public.rh_tipos_documento (id, nombre, descripcion, categoria, obligatorio, vence, vigencia_dias, orden) values
  ('ine',              'Identificación oficial (INE)', 'Por ambos lados. También sirve pasaporte vigente.', 'personal', true,  true,  null, 10),
  ('acta_nacimiento',  'Acta de nacimiento',            null,                                                'personal', true,  false, null, 20),
  ('curp',             'CURP',                          'Impresión de gob.mx/curp',                          'personal', true,  false, null, 30),
  ('domicilio',        'Comprobante de domicilio',      'Luz, agua, teléfono; no mayor a 3 meses.',          'personal', true,  false, 90,   40),
  ('estudios',         'Comprobante de estudios',       'Último grado: certificado, título o cédula.',       'personal', false, false, null, 50),
  ('solicitud',        'Solicitud de empleo o CV',      null,                                                'personal', true,  false, null, 60),
  ('recomendacion',    'Cartas de recomendación',       null,                                                'personal', false, false, null, 70),
  ('csf',              'Constancia de situación fiscal','Del SAT; con ella se timbra el CFDI de nómina (RFC, nombre, CP fiscal).', 'fiscal', true, false, null, 80),
  ('nss',              'Número de Seguridad Social',    'Constancia de NSS del IMSS.',                       'imss',     true,  false, null, 90),
  ('alta_imss',        'Alta ante el IMSS (IDSE)',      'Acuse del movimiento afiliatorio.',                 'imss',     true,  false, null, 100),
  ('infonavit',        'Aviso de retención INFONAVIT',  'Solo si tiene crédito.',                            'imss',     false, false, null, 110),
  ('fonacot',          'Crédito FONACOT',               'Solo si tiene crédito.',                            'imss',     false, false, null, 120),
  ('contrato',         'Contrato individual de trabajo','Firmado por ambas partes. LFT art. 24 y 25.',       'laboral',  true,  false, null, 130),
  ('aviso_privacidad', 'Aviso de privacidad firmado',   'Incluye el consentimiento expreso para rostro y huella (datos sensibles).', 'laboral', true, false, null, 140),
  ('reglamento',       'Reglamento interior firmado',   null,                                                'laboral',  false, false, null, 150),
  ('cuenta_bancaria',  'Estado de cuenta (CLABE)',      'Para depositar la nómina.',                         'laboral',  false, false, null, 160),
  ('examen_medico',    'Examen médico de ingreso',      'Dato sensible: solo RH.',                           'salud',    false, false, null, 170),
  ('dc3',              'Constancias DC-3',              'Capacitación (STPS). Una por curso.',               'capacitacion', false, true, null, 180),
  ('renuncia',         'Renuncia / finiquito',          'Al causar baja.',                                   'baja',     false, false, null, 190)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Documentos subidos
-- ---------------------------------------------------------------------
create table if not exists public.rh_documentos (
  id             uuid primary key default gen_random_uuid(),
  empleado_id    uuid not null references public.rh_empleados(id) on delete cascade,
  tipo_id        text not null references public.rh_tipos_documento(id),
  -- Ruta dentro del bucket "rh-expedientes": <empleado_id>/<tipo>/<archivo>
  archivo        text not null,
  nombre_archivo text,
  mime           text,
  tamano         integer,
  fecha_documento date,
  vence          date,
  notas          text,
  subido_por     uuid default auth.uid(),
  creado_at      timestamptz not null default now()
);
create index if not exists rh_documentos_emp_idx on public.rh_documentos (empleado_id, tipo_id, creado_at desc);

-- ---------------------------------------------------------------------
-- Historial de movimientos (lo llena un trigger, nadie escribe a mano)
-- ---------------------------------------------------------------------
create table if not exists public.rh_historial (
  id           bigint generated always as identity primary key,
  empleado_id  uuid not null references public.rh_empleados(id) on delete cascade,
  campo        text not null,
  antes        text,
  despues      text,
  por          uuid,
  at           timestamptz not null default now()
);
create index if not exists rh_historial_emp_idx on public.rh_historial (empleado_id, at desc);

create or replace function public._rh_historial() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  campos text[] := array['puesto','departamento','sede_id','turno_id','jefe_id','tipo',
                         'tipo_contrato','fecha_fin_contrato','salario_diario','sdi',
                         'periodicidad_pago','activo','checa_movil'];
  c text; a text; d text;
begin
  if tg_op = 'INSERT' then
    insert into rh_historial (empleado_id, campo, antes, despues, por)
    values (new.id, 'alta', null, coalesce(new.puesto, ''), auth.uid());
    return new;
  end if;
  foreach c in array campos loop
    execute format('select ($1).%I::text, ($2).%I::text', c, c) into a, d using old, new;
    if a is distinct from d then
      insert into rh_historial (empleado_id, campo, antes, despues, por)
      values (new.id, c, a, d, auth.uid());
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists rh_empleados_historial on public.rh_empleados;
create trigger rh_empleados_historial after insert or update on public.rh_empleados
  for each row execute function public._rh_historial();

-- ---------------------------------------------------------------------
-- Baja con motivo (reemplaza el uso de rh_dar_baja desde la app)
-- ---------------------------------------------------------------------
create or replace function public.rh_baja_empleado(
  p_empleado uuid, p_fecha date, p_tipo text, p_motivo text default null,
  p_recontratable boolean default true
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not rh_es_rh() then raise exception 'sin_permiso'; end if;
  perform rh_dar_baja(p_empleado);
  update rh_empleados
     set fecha_baja = coalesce(p_fecha, current_date), tipo_baja = p_tipo,
         motivo_baja = p_motivo, recontratable = p_recontratable
   where id = p_empleado;
end $$;

-- Reactivar (recontratación): limpia los datos de la baja.
create or replace function public.rh_reactivar_empleado(p_empleado uuid, p_fecha_ingreso date default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not rh_es_rh() then raise exception 'sin_permiso'; end if;
  update rh_empleados
     set activo = true, baja_at = null, fecha_baja = null, tipo_baja = null,
         motivo_baja = null, recontratable = null,
         fecha_ingreso = coalesce(p_fecha_ingreso, fecha_ingreso)
   where id = p_empleado;
end $$;

-- ---------------------------------------------------------------------
-- Storage: bucket privado para los archivos del expediente
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('rh-expedientes', 'rh-expedientes', false, 15728640,
        array['application/pdf','image/jpeg','image/png','image/heic','image/webp'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists rh_expedientes_rh on storage.objects;
create policy rh_expedientes_rh on storage.objects for all to authenticated
  using (bucket_id = 'rh-expedientes' and public.rh_es_rh())
  with check (bucket_id = 'rh-expedientes' and public.rh_es_rh());

-- ---------------------------------------------------------------------
-- RLS y permisos
-- ---------------------------------------------------------------------
alter table public.rh_tipos_documento enable row level security;
alter table public.rh_documentos      enable row level security;
alter table public.rh_historial       enable row level security;

revoke all on public.rh_tipos_documento, public.rh_documentos, public.rh_historial from anon, authenticated;
grant select, insert, update on public.rh_tipos_documento to authenticated;
grant select, insert, update, delete on public.rh_documentos to authenticated;
grant select on public.rh_historial to authenticated;

drop policy if exists rh_tipos_documento_rh on public.rh_tipos_documento;
create policy rh_tipos_documento_rh on public.rh_tipos_documento for all to authenticated
  using (rh_es_rh()) with check (rh_es_rh());
drop policy if exists rh_documentos_rh on public.rh_documentos;
create policy rh_documentos_rh on public.rh_documentos for all to authenticated
  using (rh_es_rh()) with check (rh_es_rh());
drop policy if exists rh_historial_rh on public.rh_historial;
create policy rh_historial_rh on public.rh_historial for select to authenticated
  using (rh_es_rh());

revoke execute on function public._rh_historial() from public, anon, authenticated;
revoke execute on function public.rh_baja_empleado(uuid, date, text, text, boolean) from public, anon, authenticated;
revoke execute on function public.rh_reactivar_empleado(uuid, date) from public, anon, authenticated;
grant execute on function public.rh_baja_empleado(uuid, date, text, text, boolean) to authenticated;
grant execute on function public.rh_reactivar_empleado(uuid, date) to authenticated;

notify pgrst, 'reload schema';
