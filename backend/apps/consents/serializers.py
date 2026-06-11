import json

from django.contrib.auth import get_user_model
from django.db.models import Q
from django.utils import timezone
from rest_framework import serializers

from .models import AuditLog, ConsentAgreement, ConsentSignature, IdentityVerification

User = get_user_model()


def normalize_device_info(value):
    if value in (None, ""):
        return {}
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError as exc:
            raise serializers.ValidationError("Device info must be valid JSON.") from exc
        if not isinstance(parsed, dict):
            raise serializers.ValidationError("Device info must be a JSON object.")
        return parsed
    if not isinstance(value, dict):
        raise serializers.ValidationError("Device info must be a JSON object.")
    return value


class IdentityVerificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = IdentityVerification
        fields = (
            "id",
            "selfie_image",
            "government_id_image",
            "document_type",
            "document_last_four",
            "status",
            "selfie_match_score",
            "failure_reason",
            "device_info",
            "latitude",
            "longitude",
            "location_confirmed",
            "facial_verification_confirmed",
            "device_authenticated",
            "security_checks_passed",
            "submitted_at",
            "verified_at",
        )
        read_only_fields = (
            "id",
            "status",
            "selfie_match_score",
            "failure_reason",
            "facial_verification_confirmed",
            "device_authenticated",
            "security_checks_passed",
            "submitted_at",
            "verified_at",
        )

    def validate_device_info(self, value):
        return normalize_device_info(value)


class ConsentSignatureSerializer(serializers.ModelSerializer):
    signer_name = serializers.CharField(source="signer.get_full_name", read_only=True)
    signer_phone_number = serializers.CharField(source="signer.phone_number", read_only=True)

    class Meta:
        model = ConsentSignature
        fields = (
            "id",
            "signer",
            "signer_name",
            "signer_phone_number",
            "signature_image",
            "signature_text",
            "ip_address",
            "user_agent",
            "device_info",
            "latitude",
            "longitude",
            "location_confirmed",
            "verification_status",
            "signed_at",
        )
        read_only_fields = ("id", "signer", "ip_address", "user_agent", "verification_status", "signed_at")

    def validate_device_info(self, value):
        return normalize_device_info(value)

    def validate(self, attrs):
        if not attrs.get("signature_text", "").strip():
            raise serializers.ValidationError({"signature_text": "Signature name is required."})
        if not attrs.get("signature_image"):
            raise serializers.ValidationError({"signature_image": "Live signing photo is required."})
        return attrs


class ConsentAgreementSerializer(serializers.ModelSerializer):
    creator_name = serializers.CharField(source="creator.get_full_name", read_only=True)
    participant_name = serializers.CharField(source="participant.get_full_name", read_only=True)
    participant_phone_number = serializers.CharField(write_only=True)
    signatures = ConsentSignatureSerializer(many=True, read_only=True)

    class Meta:
        model = ConsentAgreement
        fields = (
            "id",
            "creator",
            "creator_name",
            "participant",
            "participant_name",
            "participant_phone_number",
            "title",
            "terms",
            "duration_hours",
            "status",
            "starts_at",
            "expires_at",
            "requested_expires_at",
            "previous_agreement",
            "signatures",
            "created_at",
            "updated_at",
        )
        read_only_fields = (
            "id",
            "creator",
            "participant",
            "status",
            "starts_at",
            "expires_at",
            "created_at",
            "updated_at",
        )

    def validate_duration_hours(self, value):
        allowed = {24, 168, 720}
        if value not in allowed:
            raise serializers.ValidationError("Duration must be 24 hours, 7 days, or 30 days.")
        return value

    def validate_requested_expires_at(self, value):
        if value and value <= timezone.now():
            raise serializers.ValidationError("Expiration date must be in the future.")
        return value

    def validate(self, attrs):
        request = self.context["request"]
        participant_phone_number = attrs.pop("participant_phone_number")
        try:
            participant = User.objects.get(phone_number=participant_phone_number)
        except User.DoesNotExist as exc:
            raise serializers.ValidationError({"participant_phone_number": "Participant account was not found."}) from exc
        if participant == request.user:
            raise serializers.ValidationError({"participant_phone_number": "Participant must be another verified adult."})
        if not request.user.is_identity_verified or not participant.is_identity_verified:
            raise serializers.ValidationError("Both parties must complete identity verification before creating consent.")
        attrs["participant"] = participant
        return attrs

    def create(self, validated_data):
        return ConsentAgreement.objects.create(creator=self.context["request"].user, **validated_data)


class ConsentRenewSerializer(serializers.Serializer):
    duration_hours = serializers.ChoiceField(choices=[24, 168, 720], required=False)
    requested_expires_at = serializers.DateTimeField(required=False)

    def validate(self, attrs):
        if not attrs.get("duration_hours") and not attrs.get("requested_expires_at"):
            raise serializers.ValidationError("Select a duration or custom expiration date.")
        if attrs.get("requested_expires_at") and attrs["requested_expires_at"] <= timezone.now():
            raise serializers.ValidationError("Expiration date must be in the future.")
        return attrs

    def create(self, validated_data):
        agreement = self.context["agreement"]
        agreement.duration_hours = validated_data.get("duration_hours") or agreement.duration_hours
        agreement.requested_expires_at = validated_data.get("requested_expires_at")
        agreement.status = ConsentAgreement.Status.PENDING_SIGNATURES
        agreement.starts_at = None
        agreement.expires_at = None
        agreement.save(
            update_fields=[
                "duration_hours",
                "requested_expires_at",
                "status",
                "starts_at",
                "expires_at",
                "updated_at",
            ]
        )
        agreement.signatures.all().delete()
        return agreement


class AuditLogSerializer(serializers.ModelSerializer):
    actor_phone_number = serializers.CharField(source="actor.phone_number", read_only=True)

    class Meta:
        model = AuditLog
        fields = ("id", "actor", "actor_phone_number", "action", "ip_address", "user_agent", "device_info", "metadata", "created_at")
        read_only_fields = fields


def agreement_queryset_for(user):
    return ConsentAgreement.objects.filter(Q(creator=user) | Q(participant=user)).select_related("creator", "participant")
