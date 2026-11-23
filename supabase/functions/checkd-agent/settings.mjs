// Pure configuration helpers keep malformed environment JSON from crashing
// module startup, and make opaque-key versus JWT headers independently testable.
export function defaultKey(raw) {
  try {
    const values = JSON.parse(raw || '{}');
    return values && typeof values.default === 'string' ? values.default.trim() : '';
  } catch { return ''; }
}

export function serviceHeaders(key) {
  return {
    apikey: key,
    ...(key.startsWith('sb_secret_') ? {} : { authorization: 'Bearer ' + key }),
    'content-type': 'application/json',
  };
}

export function supportsImages(value, model) {
  const flag = value?.trim().toLowerCase();
  return flag ? flag === 'true' : model === 'deepseek-flash';
}
