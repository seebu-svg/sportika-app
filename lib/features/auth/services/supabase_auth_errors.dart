import 'package:sportika/features/auth/services/authentication_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One place that turns a Supabase failure into the sentence a member reads.
///
/// Copy lives here rather than in the screens for two reasons: every branch that
/// could hint at whether an address exists is reviewable side by side (email
/// enumeration), and a raw server string can never reach the UI by accident.
///
/// The codes below are asserted against gotrue 2.27 / postgrest 2.9; the fallback
/// at the bottom is mandatory, so an unrecognised code degrades to a plain
/// recovery message instead of surfacing internals.

const String _generic = 'Something went wrong. Please try again in a moment.';
const String _offline =
    'We could not reach Sportika. Check your connection and try again.';
const String _expired = 'Your session has ended. Please sign in again.';
const String _rateLimited =
    'Too many attempts. Please wait a minute and try again.';
const String _neutralEmail =
    'If that address has a Sportika account, a code is on its way.';
const String _wrongPassword = 'Email or password is incorrect.';
const String _invalidCode = 'That code is invalid or has expired.';
const String _emailUnavailable =
    'Email sign-in is unavailable right now. Please try again later.';

/// Maps a GoTrue failure. Never returns `EmailVerificationRequired`: issuing a
/// challenge requires the address the member typed, which the caller owns.
AuthenticationException mapAuthError(Object error) {
  if (error is AuthRetryableFetchException) {
    return const AuthenticationException(_offline);
  }

  if (error is AuthSessionMissingException) {
    return const AuthenticationException(_expired);
  }

  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return const AuthenticationException(_wrongPassword);
      case 'email_not_confirmed':
      case 'phone_not_confirmed':
        // The service turns this into EmailVerificationRequired, because the
        // screen has to offer a resend rather than an error.
        return const AuthenticationException(
          'Verify your email to continue.',
          field: 'email',
        );
      case 'user_already_exists':
      case 'email_exists':
      case 'email_address_invalid':
      case 'validation_failed':
      case 'signup_disabled':
        return const AuthenticationException(_neutralEmail, field: 'email');
      case 'email_address_not_authorized':
        return const AuthenticationException(
          'This address cannot receive Sportika email. Try another one.',
          field: 'email',
        );
      case 'email_provider_disabled':
      case 'provider_disabled':
      case 'otp_disabled':
        return const AuthenticationException(_emailUnavailable);
      case 'reauthentication_needed':
        return const AuthenticationException(
          'Confirm your current password to continue.',
          field: 'currentPassword',
        );
      case 'weak_password':
        return const AuthenticationException(
          'Choose a longer password, at least 8 characters.',
          field: 'password',
        );
      case 'same_password':
        return const AuthenticationException(
          'Choose a password you have not used before.',
          field: 'password',
        );
      case 'otp_expired':
      case 'token has expired or is invalid':
      case 'invalid_otp':
        return const AuthenticationException(_invalidCode, field: 'otp');
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
      case 'over_sms_send_rate_limit':
        return const AuthenticationException(_rateLimited);
      case 'session_not_found':
      case 'refresh_token_not_found':
      case 'refresh_token_already_used':
        return const AuthenticationException(_expired);
      case 'user_not_found':
        // Deliberately identical to the success message.
        return const AuthenticationException(_neutralEmail);
    }

    if (error.statusCode == '429') {
      return const AuthenticationException(_rateLimited);
    }
    if (error.statusCode == '0' || error.statusCode == null) {
      // No response at all: DNS, TLS or airplane mode.
      return const AuthenticationException(_offline);
    }
  }

  return const AuthenticationException(_generic);
}

/// Maps a failed profile write.
///
/// `complete_profile_setup` raises plain-text identifiers as the message
/// (`invalid_username`, `sports_required`, …) so the client can attach the error
/// to the field that caused it instead of showing a toast.
AuthenticationException mapProfileError(Object error) {
  if (error is PostgrestException) {
    switch (error.code) {
      case '23505':
        if (error.message.contains('profiles_username_unique')) {
          return const AuthenticationException(
            'That username is taken. Try another one.',
            field: 'handle',
          );
        }
        return const AuthenticationException(_generic);
      case '23503':
        return const AuthenticationException(
          'One of those sports is no longer available.',
        );
      case '23514':
        return const AuthenticationException(
          'Some of those details are not accepted. Check them and try again.',
        );
      case '42501':
        return const AuthenticationException('You cannot change that here.');
      case 'PGRST116':
        return const AuthenticationException(
          'Your profile could not be found. Sign in again.',
        );
    }

    switch (error.message) {
      case 'invalid_display_name':
        return const AuthenticationException(
          'Use a name between 2 and 80 characters.',
          field: 'name',
        );
      case 'invalid_username':
        return const AuthenticationException(
          'Use 3–30 characters: lowercase letters, numbers, dots or underscores.',
          field: 'handle',
        );
      case 'invalid_city':
        return const AuthenticationException(
          'Add the city you play in.',
          field: 'city',
        );
      case 'invalid_bio':
        return const AuthenticationException(
          'Keep your bio to 120 characters.',
          field: 'bio',
        );
      case 'invalid_date_of_birth':
        return const AuthenticationException(
          'Enter your date of birth as DD/MM/YYYY.',
          field: 'birthDate',
        );
      case 'invalid_gender':
      case 'invalid_play_style':
        return const AuthenticationException(
          'Choose one of the listed options.',
        );
      case 'sports_required':
        return const AuthenticationException('Pick at least one sport.');
      case 'not_authenticated':
      case 'profile_not_found':
        return const AuthenticationException(_expired);
    }
  }

  return const AuthenticationException(_generic);
}
