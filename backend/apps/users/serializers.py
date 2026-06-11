from django.contrib.auth import authenticate, get_user_model
from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ("id", "phone_number", "email", "first_name", "last_name", "role", "is_identity_verified")
        read_only_fields = ("id", "role", "is_identity_verified")


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = ("id", "phone_number", "email", "first_name", "last_name", "password")
        read_only_fields = ("id",)

    def create(self, validated_data):
        password = validated_data.pop("password")
        return User.objects.create_user(password=password, **validated_data)


class LoginSerializer(serializers.Serializer):
    phone_number = serializers.CharField()
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        user = authenticate(
            request=self.context.get("request"),
            phone_number=attrs["phone_number"],
            password=attrs["password"],
        )
        if not user:
            raise serializers.ValidationError("Invalid phone number or password.")
        if not user.is_active:
            raise serializers.ValidationError("This account is inactive.")
        refresh = RefreshToken.for_user(user)
        return {
            "user": UserSerializer(user).data,
            "refresh": str(refresh),
            "access": str(refresh.access_token),
        }
