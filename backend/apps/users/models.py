from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
from django.utils.translation import gettext_lazy as _


class UserManager(BaseUserManager):
    def _create_user(self, phone_number, password, **extra_fields):
        if not phone_number:
            raise ValueError(_("The phone number must be set"))
        user = self.model(phone_number=phone_number, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, phone_number, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", False)
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(phone_number, password, **extra_fields)

    def create_superuser(self, phone_number, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("role", CustomUser.Roles.ADMIN)
        return self._create_user(phone_number, password, **extra_fields)


class CustomUser(AbstractUser):
    class Roles(models.TextChoices):
        ADMIN = "ADMIN", "Admin"
        STAFF = "STAFF", "Staff"
        USER = "USER", "User"

    username = None
    phone_number = models.CharField(_("phone number"), max_length=20, unique=True)
    email = models.EmailField(_("email address"), blank=True, null=True)
    role = models.CharField(max_length=20, choices=Roles.choices, default=Roles.USER)
    is_identity_verified = models.BooleanField(default=False)

    USERNAME_FIELD = "phone_number"
    REQUIRED_FIELDS = ["first_name", "last_name", "email"]

    objects = UserManager()

    def __str__(self):
        return f"{self.phone_number} ({self.role})"
