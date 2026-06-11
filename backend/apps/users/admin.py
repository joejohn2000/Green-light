from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import CustomUser


@admin.register(CustomUser)
class CustomUserAdmin(UserAdmin):
    model = CustomUser
    list_display = ("id", "phone_number", "email", "first_name", "last_name", "role", "is_identity_verified")
    list_filter = ("role", "is_identity_verified", "is_staff", "is_active")
    search_fields = ("phone_number", "email", "first_name", "last_name")
    ordering = ("-date_joined",)
    fieldsets = (
        (None, {"fields": ("phone_number", "password")}),
        ("Personal info", {"fields": ("first_name", "last_name", "email")}),
        ("Green Light", {"fields": ("role", "is_identity_verified")}),
        ("Permissions", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
        ("Important dates", {"fields": ("last_login", "date_joined")}),
    )
    add_fieldsets = (
        (None, {
            "classes": ("wide",),
            "fields": ("phone_number", "email", "first_name", "last_name", "password1", "password2"),
        }),
    )
