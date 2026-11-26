# 📮 El Buzón Real

Lista de regalos familiar para Nochebuena. Cada uno apunta su carta y marca lo que va a comprar a los demás, sin que el destinatario vea qué le han comprado.

- `index.html`: la web (estática, sin dependencias).
- `supabase.sql`: esquema completo para un proyecto nuevo. Todo el acceso pasa por funciones que comprueban la contraseña; las tablas están cerradas a la clave anon.
- `migrations/`: cambios aplicados sobre el proyecto ya existente (p. ej. `002_fotos.sql`).
- `config.js`: URL y clave anon (pública por diseño) del proyecto de Supabase.
- `.github/workflows/pages.yml`: despliega en GitHub Pages. Si defines los secretos `SUPABASE_URL` y `SUPABASE_ANON_KEY`, sustituyen a `config.js`.

## Puesta en marcha
1. Supabase → SQL Editor → pegar `supabase.sql` → Run.
2. Poner la URL y la clave anon en `config.js` (o como secretos del repo).
3. Repo → Settings → Pages → Source: **GitHub Actions**.
4. Lanzar el workflow (o hacer push a `main`).
