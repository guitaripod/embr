import EmbrCore

enum AuthState: Sendable, Equatable {
    case anonymous
    case authenticated(AuthenticatedUser)
}
