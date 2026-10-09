-- 0095: Go Play WhatsApp support contact (configuration only).
-- The support number is deliberately unset until a System Admin configures it.
-- Apply this migration before deploying the matching Flutter client.
-- No existing settings value, role, policy, or notification is modified.
--
-- A member may read the number through the existing authenticated SELECT RLS.
-- Only the narrowly scoped RPC may write this one column.
-- System Admin eligibility is the existing server-side system_admins table,
-- not a community role or an email string supplied by the client.

alter table public.app_settings
  add column if not exists support_whatsapp_phone text;

comment on column public.app_settings.support_whatsapp_phone is
  'Optional WhatsApp support phone in international digits-only form (8-15 digits). NULL disables contact until configured by System Admin.';

-- Existing app_settings SELECT policy is authenticated-only. The older settings
-- columns have their own column-level grants; explicitly grant only this read.
grant select (support_whatsapp_phone)
  on public.app_settings to authenticated;

-- Do not add an UPDATE policy or any direct column UPDATE grant:
-- even administrators change only the support number through the RPC.
create or replace function public.admin_set_support_whatsapp_phone(p_phone text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := nullif(btrim(p_phone), '');
begin
  if auth.uid() is null or not public.is_system_admin() then
    raise exception 'NOT_SYSTEM_ADMIN';
  end if;

  if v_phone is not null then
    v_phone := regexp_replace(v_phone, '^\+', '');
    if v_phone !~ '^[1-9][0-9]{7,14}$' then
      raise exception 'INVALID_SUPPORT_PHONE';
    end if;
  end if;

  update public.app_settings
  set support_whatsapp_phone = v_phone
  where id = true;

  if not found then
    raise exception 'APP_SETTINGS_NOT_FOUND';
  end if;
end;
$$;

revoke execute on function public.admin_set_support_whatsapp_phone(text)
  from public, anon;
grant execute on function public.admin_set_support_whatsapp_phone(text)
  to authenticated;
