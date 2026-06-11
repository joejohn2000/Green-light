import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "green_light.settings.dev")

app = Celery("green_light")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
