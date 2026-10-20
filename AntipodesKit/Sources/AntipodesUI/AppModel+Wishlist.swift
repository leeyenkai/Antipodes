import AntipodesCore
import AntipodesStats
import Foundation

public extension AppModel {
    func isOnWishlist(_ place: PlaceReference) -> Bool {
        log.wishlist.contains { $0.place?.id == place.id }
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

    func removeFromWishlist(place: PlaceReference) {
        let ids = log.wishlist.filter { $0.place?.id == place.id && $0.routeID == nil }.map(\.id)
        removeFromWishlist(ids)
    }

    /// Wishlist places not yet visited, for the globe's wishlist pins (R-GLOBE-4).
    var openWishlistPlaces: [PlaceReference] {
        statistics.wishlist.filter { !$0.isVisited }.compactMap(\.item.place)
    }
}
