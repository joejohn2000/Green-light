from celery import shared_task
from django.utils import timezone

from .models import ConsentAgreement


@shared_task
def expire_active_agreements():
    return ConsentAgreement.objects.filter(
        status=ConsentAgreement.Status.ACTIVE,
        expires_at__lte=timezone.now(),
    ).update(status=ConsentAgreement.Status.EXPIRED)
