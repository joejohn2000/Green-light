from textwrap import wrap

from django.conf import settings
from django.db import IntegrityError
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import generics, permissions, status
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.authentication import JWTAuthentication

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
    location_metadata = {}
    if hasattr(request, "data"):
        for key in ("latitude", "longitude", "location_confirmed"):
            if key in request.data:
                location_metadata[key] = request.data.get(key)
    return AuditLog.objects.create(
        actor=request.user if request.user.is_authenticated else None,
        agreement=agreement,
        action=action,
        ip_address=client_ip(request),
        user_agent=request.META.get("HTTP_USER_AGENT", ""),
        device_info=normalize_device_info(raw_device_info),
        metadata={**location_metadata, **(metadata or {})},
    )


def pdf_escape(value):
    return str(value).replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def build_contract_pdf(agreement):
    agreement.mark_expired_if_needed()
    lines = [
        "GREEN LIGHT CONSENT AGREEMENT",
        "",
        f"Agreement ID: GL-{agreement.id:06d}",
        f"Status: {agreement.status.replace('_', ' ')}",
        f"Title: {agreement.title}",
        f"Created: {agreement.created_at:%Y-%m-%d %H:%M UTC}",
        f"Starts: {agreement.starts_at:%Y-%m-%d %H:%M UTC}" if agreement.starts_at else "Starts: Pending signatures",
        f"Expires: {agreement.expires_at:%Y-%m-%d %H:%M UTC}" if agreement.expires_at else "Expires: Pending activation",
        "",
        "PARTICIPANTS",
        f"Creator: {agreement.creator.get_full_name() or agreement.creator.phone_number}",
        f"Creator Phone: {agreement.creator.phone_number}",
        f"Creator Verified: {'Yes' if agreement.creator.is_identity_verified else 'No'}",
        f"Participant: {agreement.participant.get_full_name() or agreement.participant.phone_number}",
        f"Participant Phone: {agreement.participant.phone_number}",
        f"Participant Verified: {'Yes' if agreement.participant.is_identity_verified else 'No'}",
        "",
        "AGREEMENT TERMS",
    ]
    for paragraph in agreement.terms.splitlines() or [agreement.terms]:
        lines.extend(wrap(paragraph, width=88) or [""])
    lines.extend(["", "DIGITAL SIGNATURES"])
    for signature in agreement.signatures.select_related("signer"):
        signer = signature.signer.get_full_name() or signature.signer.phone_number
        location = "Confirmed" if signature.location_confirmed else "Not confirmed"
        lines.append(
            f"{signer} signed as '{signature.signature_text}' on "
            f"{signature.signed_at:%Y-%m-%d %H:%M UTC}; Location: {location}; Verification: {signature.verification_status}"
        )
    if not agreement.signatures.exists():
        lines.append("No signatures have been recorded yet.")
    lines.extend(["", "ACTIVITY HISTORY"])
    for log in agreement.audit_logs.exclude(action="agreement_viewed").select_related("actor"):
        actor = log.actor.phone_number if log.actor else "System"
        lines.append(f"{log.created_at:%Y-%m-%d %H:%M UTC} - {log.action.replace('_', ' ').title()} - {actor}")

    visible_lines = []
    for line in lines:
        visible_lines.extend(wrap(line, width=96) if len(line) > 96 else [line])

    text_commands = ["BT", "/F1 11 Tf", "50 790 Td", "14 TL"]
    first = True
    for line in visible_lines[:52]:
        if first:
            text_commands.append(f"({pdf_escape(line)}) Tj")
            first = False
        else:
            text_commands.append(f"T* ({pdf_escape(line)}) Tj")
    text_commands.append("ET")
    stream = "\n".join(text_commands).encode("utf-8")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>",
        b"<< /Length " + str(len(stream)).encode("ascii") + b" >>\nstream\n" + stream + b"\nendstream",
    ]
    pdf = bytearray(b"%PDF-1.4\n")
    offsets = []
    for index, obj in enumerate(objects, start=1):
        offsets.append(len(pdf))
        pdf.extend(f"{index} 0 obj\n".encode("ascii"))
        pdf.extend(obj)
        pdf.extend(b"\nendobj\n")
    xref_at = len(pdf)
    pdf.extend(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode("ascii"))
    for offset in offsets:
        pdf.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
    pdf.extend(
        f"trailer << /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_at}\n%%EOF\n".encode("ascii")
    )
    return bytes(pdf)


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
        return Response(self.get_serializer(instance).data)


class ConsentSignatureView(APIView):
    parser_classes = [MultiPartParser, FormParser]
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        agreement = get_object_or_404(agreement_queryset_for(request.user), pk=pk)
        agreement.mark_expired_if_needed()
        if agreement.status != ConsentAgreement.Status.PENDING_SIGNATURES:
            raise ValidationError("This agreement cannot be signed in its current state.")
        if not request.user.is_identity_verified:
            raise PermissionDenied("Identity verification is required before signing.")
        if request.user not in [agreement.creator, agreement.participant]:
            raise PermissionDenied("Only agreement participants can sign.")
        if agreement.signatures.filter(signer=request.user).exists():
            raise ValidationError("You have already signed this agreement.")
        serializer = ConsentSignatureSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            signature = serializer.save(
                agreement=agreement,
                signer=request.user,
                ip_address=client_ip(request),
                user_agent=request.META.get("HTTP_USER_AGENT", ""),
                verification_status="VERIFIED" if request.user.is_identity_verified else "PENDING",
            )
        except IntegrityError as exc:
            if "unique_signature_per_agreement_signer" in str(exc):
                raise ValidationError("You have already signed this agreement.") from exc
            raise
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
        renewed_agreement = serializer.save()
        write_audit(
            request,
            "agreement_renewed",
            renewed_agreement,
            {"requires_new_signatures": True},
        )
        return Response(ConsentAgreementSerializer(renewed_agreement, context={"request": request}).data)


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
        return agreement.audit_logs.exclude(action="agreement_viewed").select_related("actor")


class AgreementPDFDownloadView(APIView):
    authentication_classes = []
    permission_classes = []

    def get_user(self, request):
        if request.user.is_authenticated:
            return request.user
        raw_token = request.query_params.get("access_token")
        if not raw_token:
            raise PermissionDenied("Authentication credentials were not provided.")
        authenticator = JWTAuthentication()
        return authenticator.get_user(authenticator.get_validated_token(raw_token))

    def get(self, request, pk):
        user = self.get_user(request)
        agreement = get_object_or_404(
            agreement_queryset_for(user).prefetch_related("signatures", "audit_logs"),
            pk=pk,
        )
        write_audit(request, "agreement_downloaded", agreement)
        response = HttpResponse(build_contract_pdf(agreement), content_type="application/pdf")
        response["Content-Disposition"] = f'attachment; filename="green-light-agreement-{agreement.id}.pdf"'
        return response
