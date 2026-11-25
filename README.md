# 📮 El Buzón Real

Lista de regalos familiar para Nochebuena. Cada uno apunta su carta y marca lo que va a comprar a los demás, sin que el destinatario vea qué le han comprado.

- `index.html`: la web (estática, sin dependencias).
- `supabase.sql`: tablas y funciones. Todo el acceso pasa por funciones que comprueban la contraseña; las tablas están cerradas a la clave anon.
- `.github/workflows/pages.yml`: despliega en GitHub Pages y genera `config.js` con los secretos `SUPABASE_URL` y `SUPABASE_ANON_KEY`.

## Puesta en marcha
1. Supabase → SQL Editor → pegar `supabase.sql` → Run.
2. Repo → Settings → Secrets and variables → Actions: crear `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
3. Repo → Settings → Pages → Source: **GitHub Actions**.
4. Lanzar el workflow (o hacer push a `main`).
