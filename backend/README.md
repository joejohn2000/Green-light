# Green Light Backend

Django/DRF backend modeled after the Ambuone backend stack.

## Local setup

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements/dev.txt
cp .env.example .env
python manage.py migrate
python manage.py runserver
```

Core API roots:

- `POST /api/users/register/`
- `POST /api/users/login/`
- `POST /api/consents/identity-verifications/`
- `GET|POST /api/consents/agreements/`
- `POST /api/consents/agreements/<id>/sign/`
- `POST /api/consents/agreements/<id>/renew/`
- `GET /api/consents/agreements/<id>/audit/`
