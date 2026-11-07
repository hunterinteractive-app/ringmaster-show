import { checkedRefresh, needsRefresh, parseCredentials } from './credentials.ts';
const jwt = (exp: number) => 'test.' + btoa(JSON.stringify({exp})) + '.signature';
Deno.test('legacy access-only and new sealed credential payloads remain readable', () => {
  if (parseCredentials(jwt(9999)).access_token !== jwt(9999)) throw Error('legacy');
  const creds = {access_token: jwt(9999), refresh_token: 'server-only'};
  if (parseCredentials(JSON.stringify(creds)).refresh_token !== creds.refresh_token) throw Error('refresh');
});
Deno.test('rotate before token expiry, not on every activity request', () => {
  if (needsRefresh(jwt(2000),1000) || !needsRefresh(jwt(1299),1000) || !needsRefresh(jwt(999),1000)) throw Error('refresh threshold');
});
Deno.test('renewal must retain the intended user and both credentials', () => {
  const result = {user:{id:'target'},session:{access_token:jwt(2000),refresh_token:'new'}};
  if (checkedRefresh('target',result).refresh_token !== 'new') throw Error('valid');
  for (const bad of [{...result,user:{id:'other'}},{...result,session:null}]) {
    let denied=false; try { checkedRefresh('target',bad); } catch { denied=true; }
    if (!denied) throw Error('unsafe renewal');
  }
});
