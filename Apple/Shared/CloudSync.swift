// Cloud sync is deliberately disabled in this local Mac release.
// The iPhone build and entitlement-backed CloudKit integration are deferred.
enum CloudSync {
    static let isEnabled = false
}
