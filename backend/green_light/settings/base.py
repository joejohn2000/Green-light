from datetime import timedelta
from pathlib import Path
from urllib.parse import urlparse

import environ

BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env(DEBUG=(bool, False))
environ.Env.read_env(BASE_DIR / ".env")


def normalize_host(value):
    value = value.strip().rstrip("/")
    if not value:
        return value
    parsed = urlparse(value if "://" in value else f"//{value}")
    return parsed.netloc or parsed.path


def normalize_origin(value):
    value = value.strip().rstrip("/")
    if not value:
        return value
    parsed = urlparse(value)
    if parsed.scheme and parsed.netloc:
        return f"{parsed.scheme}://{parsed.netloc}"
    return value


SECRET_KEY = env("SECRET_KEY", default="unsafe-dev-secret-key")
DEBUG = env("DEBUG")
ALLOWED_HOSTS = [
    host for host in (normalize_host(item) for item in env.list("ALLOWED_HOSTS", default=[]))
    if host
]
CSRF_TRUSTED_ORIGINS = [
    origin for origin in (
        normalize_origin(item) for item in env.list("CSRF_TRUSTED_ORIGINS", default=[])
    )
    if origin
]

INSTALLED_APPS = [
    "daphne",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "rest_framework",
    "rest_framework_simplejwt",
    "rest_framework_simplejwt.token_blacklist",
    "django_filters",
    "django_celery_results",
    "channels",
    "apps.users",
    "apps.consents",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "green_light.urls"
WSGI_APPLICATION = "green_light.wsgi.application"
ASGI_APPLICATION = "green_light.asgi.application"

DATABASES = {
    "default": env.db("DATABASE_URL", default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}"),
}
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
AUTH_USER_MODEL = "users.CustomUser"

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STATICFILES_STORAGE = "whitenoise.storage.CompressedManifestStaticFilesStorage"
MEDIA_URL = "media/"
MEDIA_ROOT = BASE_DIR / "media"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    "DEFAULT_FILTER_BACKENDS": (
        "django_filters.rest_framework.DjangoFilterBackend",
    ),
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=env.int("ACCESS_TOKEN_LIFETIME_MINUTES", default=60)),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=env.int("REFRESH_TOKEN_LIFETIME_DAYS", default=7)),
}

CORS_ALLOWED_ORIGINS = [
    origin for origin in (
        normalize_origin(item) for item in env.list("CORS_ALLOWED_ORIGINS", default=[])
    )
    if origin
]
CORS_ALLOW_CREDENTIALS = True

REDIS_URL = env("REDIS_URL", default="redis://127.0.0.1:6379")
CELERY_BROKER_URL = REDIS_URL
CELERY_RESULT_BACKEND = REDIS_URL
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"

AUTO_APPROVE_IDENTITY_VERIFICATION = env.bool(
    "AUTO_APPROVE_IDENTITY_VERIFICATION",
    default=DEBUG,
)

CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {"hosts": [REDIS_URL]},
    },
}

CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": REDIS_URL,
        "OPTIONS": {
            "CLIENT_CLASS": "django_redis.client.DefaultClient",
            "IGNORE_EXCEPTIONS": env.bool("REDIS_IGNORE_EXCEPTIONS", default=True),
        },
    }
}

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "root": {"handlers": ["console"], "level": "INFO"},
}
