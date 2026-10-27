// Runtime configuration, all from environment variables (see README.md).
import path from 'node:path';

const env = process.env;
const int = (v, d) => (v === undefined || v === '' ? d : Number.parseInt(v, 10));

export function loadConfig(overrides = {}) {
  const dataDir = path.resolve(overrides.dataDir ?? env.QREAD_DATA_DIR ?? './data');
  return {
    host: overrides.host ?? env.QREAD_HOST ?? '127.0.0.1',
    port: overrides.port ?? int(env.QREAD_PORT, 8920),
    dataDir,
    dbPath: overrides.dbPath ?? env.QREAD_DB ?? path.join(dataDir, 'qread.db'),
    // public origin, used in absolute URLs the app downloads from (avatars, theme files, vip page)
    baseUrl: (overrides.baseUrl ?? env.QREAD_BASE_URL ?? 'http://127.0.0.1:8920').replace(/\/+$/, ''),
    // registration: 'invite' = needs an admin-issued 6-digit code in the `code` field; 'closed' = no self-registration
    register: overrides.register ?? env.QREAD_REGISTER ?? 'invite',
    // 'off' = getEmailCode does nothing; 'log' = the code is only written to the journal (owner reads it)
    mail: overrides.mail ?? env.QREAD_MAIL ?? 'off',
    tokenTtlDays: overrides.tokenTtlDays ?? int(env.QREAD_TOKEN_TTL_DAYS, 365),
    freeBackupDevices: overrides.freeBackupDevices ?? int(env.QREAD_FREE_BACKUP_DEVICES, 2),
    maxLoginDevices: overrides.maxLoginDevices ?? int(env.QREAD_MAX_LOGIN_DEVICES, 20),
    maxBodyBytes: overrides.maxBodyBytes ?? int(env.QREAD_MAX_BODY_BYTES, 32 * 1024 * 1024),
    trustProxy: overrides.trustProxy ?? (env.QREAD_TRUST_PROXY ?? '1') !== '0',
    // cloud features require membership (the original gates them client side; here the server enforces it too)
    cloudNeedsVip: overrides.cloudNeedsVip ?? (env.QREAD_CLOUD_NEEDS_VIP ?? '1') !== '0',
    log: overrides.log ?? (env.QREAD_LOG ?? '1') !== '0',
  };
}
