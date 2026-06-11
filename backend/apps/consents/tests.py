import shutil
import tempfile

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from .models import ConsentAgreement

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
