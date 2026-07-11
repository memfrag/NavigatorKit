import NavigatorKit

/// The reviews feature's public routes. Other features link to reviews by
/// navigating to these values — without depending on the implementation.
public enum ReviewRoute: Route {
    case compose(productID: Int)
    case photoPicker
}
