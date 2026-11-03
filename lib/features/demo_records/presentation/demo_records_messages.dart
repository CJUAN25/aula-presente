import '../domain/demo_records_repository.dart';

String demoRecordsErrorMessage(Object? error) {
  if (error is! DemoRecordsFailure) {
    return 'No pudimos completar la solicitud. Inténtalo de nuevo.';
  }
  return switch (error.kind) {
    DemoRecordsFailureKind.signedOut =>
      'Tu sesión terminó. Inicia sesión de nuevo para continuar.',
    DemoRecordsFailureKind.emailNotVerified =>
      'Verifica tu correo para consultar y administrar estos registros.',
    DemoRecordsFailureKind.permissionDenied => 'Firebase no autorizó esta operación. Comprueba tu sesión y que el correo esté verificado.',
    DemoRecordsFailureKind.network => 'No pudimos conectar con el servicio. Revisa tu conexión e inténtalo otra vez.',
    DemoRecordsFailureKind.notFound =>
      'El registro ya no está disponible. Actualiza la lista.',
    DemoRecordsFailureKind.invalidData => 'No pudimos leer el registro porque sus datos no tienen el formato esperado.',
    DemoRecordsFailureKind.unknown =>
      'No pudimos completar la solicitud. Inténtalo de nuevo.',
  };
}
