from django.urls import path

from .views import (
    AgreementAuditTrailView,
    ConsentAgreementDetailView,
    ConsentAgreementListCreateView,
    ConsentRenewView,
    ConsentRevokeView,
    ConsentSignatureView,
    IdentityVerificationView,
)

urlpatterns = [
    path("identity-verifications/", IdentityVerificationView.as_view(), name="identity-verifications"),
    path("agreements/", ConsentAgreementListCreateView.as_view(), name="agreement-list-create"),
    path("agreements/<int:pk>/", ConsentAgreementDetailView.as_view(), name="agreement-detail"),
    path("agreements/<int:pk>/sign/", ConsentSignatureView.as_view(), name="agreement-sign"),
    path("agreements/<int:pk>/renew/", ConsentRenewView.as_view(), name="agreement-renew"),
    path("agreements/<int:pk>/revoke/", ConsentRevokeView.as_view(), name="agreement-revoke"),
    path("agreements/<int:pk>/audit/", AgreementAuditTrailView.as_view(), name="agreement-audit"),
]
