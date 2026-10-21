import AntipodesCore
import AntipodesStats
import Foundation

public extension AppModel {
    /// Whether this place is on the wishlist in its own right. A wishlisted route also
    /// records where it starts, but that does not put its first station on the list.
    func isOnWishlist(_ place: PlaceReference) -> Bool {
        log.wishlist.contains { $0.place?.id == place.id && $0.routeID == nil }
    }

    func isOnWishlist(routeID: Int64) -> Bool {
        log.wishlist.contains { $0.routeID == routeID }
    }

    func addToWishlist(_ place: PlaceReference) {
        guard !isOnWishlist(place) else { return }
        perform { try store.addToWishlist(WishlistItem(place: place, createdAt: Date())) }
    }

    func addToWishlist(route: RouteInfo) {
        guard !isOnWishlist(routeID: route.id) else { return }
        perform {
            try store.addToWishlist(
                WishlistItem(
                    place: route.start,
                    routeID: route.id,
                    routeName: route.name,
                    createdAt: Date()
                )
            )
        }
    }

    func removeFromWishlist(_ ids: [UUID]) {
        perform { try store.removeFromWishlist(ids) }
    }

    /// Adds the place, or takes it off if it is there already. Says which it did.
    @discardableResult
    func toggleWishlist(_ place: PlaceReference) -> Bool {
        if isOnWishlist(place) {
            removeFromWishlist(place: place)
            return false
        }
        addToWishlist(place)
        return true
    }

    func removeFromWishlist(place: PlaceReference) {
        let ids = log.wishlist.filter { $0.place?.id == place.id && $0.routeID == nil }.map(\.id)
        removeFromWishlist(ids)
    }

    /// Wishlist places not yet visited, for the globe's wishlist pins (R-GLOBE-4).
    var openWishlistPlaces: [PlaceReference] {
        statistics.wishlist.filter { !$0.isVisited }.compactMap(\.item.place)
    }
}
