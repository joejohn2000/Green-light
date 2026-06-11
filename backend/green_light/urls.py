from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from rest_framework.response import Response
from rest_framework.views import APIView


class HealthCheckView(APIView):
    authentication_classes = []
    permission_classes = []

    def get(self, request):
        return Response({"status": "ok", "service": "green-light"})


urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/health/", HealthCheckView.as_view(), name="health-check"),
    path("api/users/", include("apps.users.urls")),
    path("api/consents/", include("apps.consents.urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
