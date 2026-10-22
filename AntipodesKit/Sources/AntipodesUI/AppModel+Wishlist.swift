import AntipodesCore
import AntipodesGlobe
import AntipodesStats
import Foundation

public extension AppModel {
    /// Whether this place is on the wishlist in its own right. A wishlisted route also
    /// records where it starts, but that does not put its first station on the list.
    func isOnWishlist(_ place: PlaceReference) -> Bool {
        log.wishlist.contains { $0.wishedPlace?.id == place.id }
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
        let removed = log.wishlist.filter { ids.contains($0.id) }
        if perform({ try store.removeFromWishlist(ids) }), !removed.isEmpty {
            offerUndo(Deletion(
                message: removed.count == 1
                    ? "Removed \(removed[0].title) from your wishlist"
                    : "Removed \(removed.count) from your wishlist",
                records: TravelLog(wishlist: removed)
            ))
        }
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
        let ids = log.wishlist.filter { $0.wishedPlace?.id == place.id }.map(\.id)
        removeFromWishlist(ids)
    }

    /// Wishlist places not yet visited, for the globe's wishlist pins (R-GLOBE-4).
    var openWishlistPlaces: [PlaceReference] {
        statistics.wishlist.filter { !$0.isVisited }.compactMap(\.item.wishedPlace)
    }

    /// Catalogue routes still on the wishlist whose two ends are known places, to draw
    /// as dashed lines on the globe.
    var openWishlistRoutes: [GlobeWishlistRoute] {
        statistics.wishlist.filter { !$0.isVisited }.compactMap { status in
            guard let id = status.item.routeID, let route = route(id: id),
                  let start = route.start?.coordinate, let end = route.end?.coordinate
            else { return nil }
            return GlobeWishlistRoute(id: status.item.id, name: route.name, from: start, to: end)
        }
    }
}
