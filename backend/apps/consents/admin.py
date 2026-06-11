from django.contrib import admin

from .models import AuditLog, ConsentAgreement, ConsentSignature, IdentityVerification


@admin.register(IdentityVerification)
class IdentityVerificationAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "document_type", "status", "selfie_match_score", "submitted_at", "verified_at")
    list_filter = ("status", "document_type")
    search_fields = ("user__phone_number", "user__email")


class ConsentSignatureInline(admin.TabularInline):
    model = ConsentSignature
    extra = 0
    readonly_fields = ("signed_at", "ip_address", "user_agent")


class AuditLogInline(admin.TabularInline):
    model = AuditLog
    extra = 0
    readonly_fields = ("actor", "action", "ip_address", "user_agent", "metadata", "created_at")


@admin.register(ConsentAgreement)
class ConsentAgreementAdmin(admin.ModelAdmin):
    list_display = ("id", "title", "creator", "participant", "status", "duration_hours", "starts_at", "expires_at")
    list_filter = ("status", "duration_hours")
    search_fields = ("title", "creator__phone_number", "participant__phone_number")
    inlines = [ConsentSignatureInline, AuditLogInline]


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    list_display = ("id", "action", "actor", "agreement", "ip_address", "created_at")
    list_filter = ("action",)
    search_fields = ("actor__phone_number", "agreement__title", "ip_address")
