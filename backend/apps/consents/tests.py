import shutil
import tempfile
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from .models import AuditLog, ConsentAgreement

User = get_user_model()


GIF_BYTES = (
    b"GIF87a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff,"
    b"\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;"
)


def image_file(name):
    return SimpleUploadedFile(name, GIF_BYTES, content_type="image/gif")


class ConsentSignatureTests(APITestCase):
    def setUp(self):
        self.media_root = tempfile.mkdtemp()
        self.settings_override = override_settings(
            MEDIA_ROOT=self.media_root,
            ALLOWED_HOSTS=["testserver"],
        )
        self.settings_override.enable()
        self.creator = User.objects.create_user(
            phone_number="+15550000001",
            password="pass12345",
            first_name="Test",
            last_name="One",
            email="one@example.com",
            is_identity_verified=True,
        )
        self.participant = User.objects.create_user(
            phone_number="+15550000002",
            password="pass12345",
            first_name="Test",
            last_name="Two",
            email="two@example.com",
            is_identity_verified=True,
        )
        self.agreement = ConsentAgreement.objects.create(
            creator=self.creator,
            participant=self.participant,
            title="Photo signing agreement",
            terms="Both parties consent to these terms.",
            duration_hours=24,
        )

    def tearDown(self):
        self.settings_override.disable()
        shutil.rmtree(self.media_root, ignore_errors=True)

    def test_signing_requires_live_photo_and_activates_after_both_sign(self):
        url = f"/api/consents/agreements/{self.agreement.id}/sign/"
        self.client.force_authenticate(self.creator)

        missing_photo = self.client.post(
            url,
            {"signature_text": "Test One", "device_info": "{}"},
            format="multipart",
        )
        self.assertEqual(missing_photo.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.agreement.signatures.count(), 0)

        first_signature = self.client.post(
            url,
            {
                "signature_text": "Test One",
                "signature_image": image_file("creator.gif"),
                "device_info": "{}",
            },
            format="multipart",
        )
        self.assertEqual(first_signature.status_code, status.HTTP_201_CREATED)
        self.agreement.refresh_from_db()
        self.assertEqual(self.agreement.status, ConsentAgreement.Status.PENDING_SIGNATURES)

        duplicate_signature = self.client.post(
            url,
            {
                "signature_text": "Test One",
                "signature_image": image_file("creator-again.gif"),
                "device_info": "{}",
            },
            format="multipart",
        )
        self.assertEqual(duplicate_signature.status_code, status.HTTP_400_BAD_REQUEST)

        self.client.force_authenticate(self.participant)
        second_signature = self.client.post(
            url,
            {
                "signature_text": "Test Two",
                "signature_image": image_file("participant.gif"),
                "device_info": "{}",
            },
            format="multipart",
        )
        self.assertEqual(second_signature.status_code, status.HTTP_201_CREATED)
        self.agreement.refresh_from_db()
        self.assertEqual(self.agreement.status, ConsentAgreement.Status.ACTIVE)
        self.assertEqual(self.agreement.signatures.count(), 2)

    def test_custom_renewal_accepts_calendar_expiration_without_preset_duration(self):
        self.client.force_authenticate(self.creator)
        next_expiration = timezone.now() + timedelta(days=1)

        response = self.client.post(
            f"/api/consents/agreements/{self.agreement.id}/renew/",
            {
                "duration_hours": "23",
                "requested_expires_at": next_expiration.isoformat(),
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.agreement.refresh_from_db()
        self.assertEqual(self.agreement.status, ConsentAgreement.Status.PENDING_SIGNATURES)
        self.assertIsNotNone(self.agreement.requested_expires_at)

    def test_viewing_agreement_is_not_shown_in_activity_history(self):
        self.client.force_authenticate(self.creator)
        AuditLog.objects.create(
            actor=self.creator,
            agreement=self.agreement,
            action="agreement_viewed",
        )
        AuditLog.objects.create(
            actor=self.creator,
            agreement=self.agreement,
            action="agreement_created",
        )

        detail_response = self.client.get(f"/api/consents/agreements/{self.agreement.id}/")
        self.assertEqual(detail_response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            AuditLog.objects.filter(agreement=self.agreement, action="agreement_viewed").count(),
            1,
        )

        audit_response = self.client.get(f"/api/consents/agreements/{self.agreement.id}/audit/")
        self.assertEqual(audit_response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            [entry["action"] for entry in audit_response.data],
            ["agreement_created"],
        )
