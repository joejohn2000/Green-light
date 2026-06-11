from django.shortcuts import get_object_or_404
from django.conf import settings
from rest_framework import generics, permissions, status
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import AuditLog, ConsentAgreement, ConsentSignature, IdentityVerification
from .serializers import (
    AuditLogSerializer,
    ConsentAgreementSerializer,
    ConsentRenewSerializer,
    ConsentSignatureSerializer,
    IdentityVerificationSerializer,
    agreement_queryset_for,
    normalize_device_info,
)


def client_ip(request):
    forwarded = request.META.get("HTTP_X_FORWARDED_FOR")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.META.get("REMOTE_ADDR")


def write_audit(request, action, agreement=None, metadata=None):
    raw_device_info = request.data.get("device_info", {}) if hasattr(request, "data") else {}
    return AuditLog.objects.create(
        actor=request.user if request.user.is_authenticated else None,
        agreement=agreement,
        action=action,
        ip_address=client_ip(request),
        user_agent=request.META.get("HTTP_USER_AGENT", ""),
        device_info=normalize_device_info(raw_device_info),
        metadata=metadata or {},
    )


class IdentityVerificationView(generics.ListCreateAPIView):
    serializer_class = IdentityVerificationSerializer
    parser_classes = [MultiPartParser, FormParser]

    def get_queryset(self):
        return IdentityVerification.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        verification = serializer.save(user=self.request.user)
        if settings.AUTO_APPROVE_IDENTITY_VERIFICATION:
            verification.mark_verified(score=100)
        write_audit(self.request, "identity_verification_submitted", metadata={"verification_id": verification.id})


class ConsentAgreementListCreateView(generics.ListCreateAPIView):
    serializer_class = ConsentAgreementSerializer

    def get_queryset(self):
        queryset = agreement_queryset_for(self.request.user)
        status_value = self.request.query_params.get("status")
        if status_value:
            queryset = queryset.filter(status=status_value)
        for agreement in queryset:
            agreement.mark_expired_if_needed()
        return queryset

    def perform_create(self, serializer):
        agreement = serializer.save()
        write_audit(self.request, "agreement_created", agreement, {"duration_hours": agreement.duration_hours})


class ConsentAgreementDetailView(generics.RetrieveAPIView):
    serializer_class = ConsentAgreementSerializer

    def get_queryset(self):
        return agreement_queryset_for(self.request.user).prefetch_related("signatures")

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.mark_expired_if_needed()
        write_audit(request, "agreement_viewed", instance)
        return Response(self.get_serializer(instance).data)


class ConsentSignatureView(APIView):
    parser_classes = [MultiPartParser, FormParser]
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        agreement = get_object_or_404(agreement_queryset_for(request.user), pk=pk)
        agreement.mark_expired_if_needed()
        if agreement.status not in [ConsentAgreement.Status.PENDING_SIGNATURES, ConsentAgreement.Status.ACTIVE]:
            raise ValidationError("This agreement cannot be signed in its current state.")
        if not request.user.is_identity_verified:
            raise PermissionDenied("Identity verification is required before signing.")
        if request.user not in [agreement.creator, agreement.participant]:
            raise PermissionDenied("Only agreement participants can sign.")
        serializer = ConsentSignatureSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        signature = serializer.save(
            agreement=agreement,
            signer=request.user,
            ip_address=client_ip(request),
            user_agent=request.META.get("HTTP_USER_AGENT", ""),
        )
        activated = agreement.activate_if_ready()
        write_audit(
            request,
            "agreement_signed",
            agreement,
            {"signature_id": signature.id, "activated": activated},
        )
        return Response(ConsentAgreementSerializer(agreement, context={"request": request}).data, status=status.HTTP_201_CREATED)


class ConsentRenewView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        agreement = get_object_or_404(agreement_queryset_for(request.user), pk=pk)
        serializer = ConsentRenewSerializer(data=request.data, context={"request": request, "agreement": agreement})
        serializer.is_valid(raise_exception=True)
        renewed = serializer.save()
        write_audit(request, "agreement_renewed", renewed, {"previous_agreement_id": agreement.id})
        return Response(ConsentAgreementSerializer(renewed, context={"request": request}).data, status=status.HTTP_201_CREATED)


class ConsentRevokeView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        agreement = get_object_or_404(agreement_queryset_for(request.user), pk=pk)
        if agreement.status not in [ConsentAgreement.Status.ACTIVE, ConsentAgreement.Status.PENDING_SIGNATURES]:
            raise ValidationError("This agreement cannot be revoked in its current state.")
        agreement.status = ConsentAgreement.Status.REVOKED
        agreement.save(update_fields=["status", "updated_at"])
        write_audit(request, "agreement_revoked", agreement)
        return Response(ConsentAgreementSerializer(agreement, context={"request": request}).data)


class AgreementAuditTrailView(generics.ListAPIView):
    serializer_class = AuditLogSerializer

    def get_queryset(self):
        agreement = get_object_or_404(agreement_queryset_for(self.request.user), pk=self.kwargs["pk"])
        return agreement.audit_logs.select_related("actor")
