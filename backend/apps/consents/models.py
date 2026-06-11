from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone


class IdentityVerification(models.Model):
    class Status(models.TextChoices):
        PENDING = "PENDING", "Pending"
        VERIFIED = "VERIFIED", "Verified"
        REJECTED = "REJECTED", "Rejected"

    class DocumentType(models.TextChoices):
        PASSPORT = "PASSPORT", "Passport"
        DRIVING_LICENSE = "DRIVING_LICENSE", "Driving license"
        NATIONAL_ID = "NATIONAL_ID", "National ID"
        OTHER = "OTHER", "Other"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="identity_checks")
    selfie_image = models.ImageField(upload_to="identity/selfies/")
    government_id_image = models.ImageField(upload_to="identity/government_ids/")
    document_type = models.CharField(max_length=30, choices=DocumentType.choices)
    document_last_four = models.CharField(max_length=4, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    selfie_match_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    failure_reason = models.TextField(blank=True)
    device_info = models.JSONField(default=dict, blank=True)
    submitted_at = models.DateTimeField(auto_now_add=True)
    verified_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-submitted_at",)

    def mark_verified(self, score=None):
        self.status = self.Status.VERIFIED
        self.selfie_match_score = score
        self.verified_at = timezone.now()
        self.user.is_identity_verified = True
        self.user.save(update_fields=["is_identity_verified"])
        self.save(update_fields=["status", "selfie_match_score", "verified_at"])

    def __str__(self):
        return f"{self.user_id} - {self.status}"


class ConsentAgreement(models.Model):
    class Status(models.TextChoices):
        DRAFT = "DRAFT", "Draft"
        PENDING_SIGNATURES = "PENDING_SIGNATURES", "Pending signatures"
        ACTIVE = "ACTIVE", "Active"
        EXPIRED = "EXPIRED", "Expired"
        REVOKED = "REVOKED", "Revoked"

    creator = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="created_agreements")
    participant = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="received_agreements")
    title = models.CharField(max_length=180, default="Mutual Consent Agreement")
    terms = models.TextField()
    duration_hours = models.PositiveIntegerField(default=24)
    status = models.CharField(max_length=30, choices=Status.choices, default=Status.PENDING_SIGNATURES)
    starts_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    previous_agreement = models.ForeignKey("self", on_delete=models.SET_NULL, null=True, blank=True, related_name="renewals")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)

    @property
    def is_fully_signed(self):
        return self.signatures.values("signer_id").distinct().count() == 2

    def activate_if_ready(self):
        if self.status == self.Status.PENDING_SIGNATURES and self.is_fully_signed:
            now = timezone.now()
            self.status = self.Status.ACTIVE
            self.starts_at = now
            self.expires_at = now + timedelta(hours=self.duration_hours)
            self.save(update_fields=["status", "starts_at", "expires_at", "updated_at"])
            return True
        return False

    def mark_expired_if_needed(self):
        if self.status == self.Status.ACTIVE and self.expires_at and self.expires_at <= timezone.now():
            self.status = self.Status.EXPIRED
            self.save(update_fields=["status", "updated_at"])
            return True
        return False

    def __str__(self):
        return f"{self.title} ({self.status})"


class ConsentSignature(models.Model):
    agreement = models.ForeignKey(ConsentAgreement, on_delete=models.CASCADE, related_name="signatures")
    signer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="consent_signatures")
    signature_image = models.ImageField(upload_to="consents/signatures/", null=True, blank=True)
    signature_text = models.CharField(max_length=180, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(blank=True)
    device_info = models.JSONField(default=dict, blank=True)
    signed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("signed_at",)
        constraints = [
            models.UniqueConstraint(fields=["agreement", "signer"], name="unique_signature_per_agreement_signer")
        ]

    def __str__(self):
        return f"{self.signer_id} signed {self.agreement_id}"


class AuditLog(models.Model):
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    agreement = models.ForeignKey(ConsentAgreement, on_delete=models.CASCADE, null=True, blank=True, related_name="audit_logs")
    action = models.CharField(max_length=80)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(blank=True)
    device_info = models.JSONField(default=dict, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self):
        return f"{self.action} by {self.actor_id}"
