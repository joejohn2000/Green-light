FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements /app/requirements
RUN pip install --no-cache-dir -r requirements/prod.txt

COPY . /app

CMD ["gunicorn", "green_light.wsgi:application", "--bind", "0.0.0.0:8000"]
