#if DEBUG
    import AntipodesCore
    import Foundation

    /// A realistic log built from real database places, for development and screenshots.
    ///
    /// Debug builds only, and only when launched with `-seedSampleData` into an empty
    /// log — it can never touch a real user's data.
    extension AppModel {
        public static var wantsSampleData: Bool {
            ProcessInfo.processInfo.arguments.contains("-seedSampleData")
        }

        public func seedSampleDataIfRequested() async {
            guard Self.wantsSampleData, log.isEmpty else { return }
            hasCompletedOnboarding = true
            if home == nil {
                home = await place("Oslo", .city)
            }
            do {
                try await seedSampleData()
            } catch {
                errorMessage = "Sample data failed: \(error)"
            }
        }

        private func place(_ name: String, _ kind: PlaceKind) async -> PlaceReference? {
            await search(name, kinds: [kind]).first?.placeReference
        }

        private func day(_ iso: String) -> FlexibleDate {
            CalendarDate(iso: iso).map(FlexibleDate.day) ?? .unknown
        }

        private func span(_ from: String, _ to: String) -> FlexibleDate {
            guard let start = CalendarDate(iso: from),
                  let end = CalendarDate(iso: to) else { return .unknown }
            return .span(start, end)
        }

        private func time(_ iso: String) -> LocalDateTime? {
            LocalDateTime(iso: iso)
        }

        private func flight(
            _ from: String,
            _ to: String,
            on date: String,
            departs: String,
            arrives: String,
            actualArrival: String? = nil,
            airline: String,
            number: String,
            aircraft: String,
            travelClass: String = "Economy"
        ) async -> JourneyLeg? {
            guard let origin = await airport(code: from),
                  let destination = await airport(code: to) else {
                return nil
            }
            return JourneyLeg(
                mode: .flight,
                origin: origin,
                destination: destination,
                date: day(date),
                times: LegTimes(
                    scheduledDeparture: time("\(date)T\(departs)"),
                    scheduledArrival: time(arrives.contains("T") ? arrives : "\(date)T\(arrives)"),
                    actualArrival: actualArrival
                        .flatMap { time($0.contains("T") ? $0 : "\(date)T\($0)") }
                ),
                operatorName: airline,
                serviceNumber: number,
                vehicle: aircraft,
                travelClass: travelClass
            )
        }

        private func ground(
            _ mode: TravelMode,
            _ from: String,
            _ to: String,
            on date: String,
            departs: String? = nil,
            arrives: String? = nil,
            operatorName: String? = nil,
            travelClass: String? = nil,
            route: Int64? = nil
        ) async -> JourneyLeg? {
            guard let origin = await place(from, .city),
                  let destination = await place(to, .city) else {
                return nil
            }
            let catalogue = route.flatMap { self.route(id: $0) }
            return JourneyLeg(
                mode: mode,
                origin: origin,
                destination: destination,
                date: day(date),
                storedPathLengthKm: catalogue?.lengthKm,
                times: LegTimes(
                    scheduledDeparture: departs.flatMap { time("\(date)T\($0)") },
                    scheduledArrival: arrives.flatMap { time("\(date)T\($0)") }
                ),
                routeID: catalogue?.id,
                routeName: catalogue?.name,
                operatorName: operatorName,
                travelClass: travelClass
            )
        }

        private func visit(
            _ name: String,
            _ kind: PlaceKind,
            _ date: FlexibleDate,
            _ type: VisitType = .stayed,
            trip: StoredTripID?,
            rating: Int? = nil
        ) async throws {
            guard let place = await place(name, kind) else { return }
            try logVisit(
                place: place,
                visitType: type,
                date: date,
                tripID: trip?.id,
                rating: rating
            )
        }

        private struct StoredTripID {
            let id: UUID
        }

        private func trip(_ name: String) throws -> StoredTripID {
            try StoredTripID(id: createTrip(name: name).id)
        }

        // A fixed script of sample records.
        // swiftlint:disable cyclomatic_complexity function_body_length
        private func seedSampleData() async throws {
            // Japan, spring 2024.
            let japan = try trip("Japan in spring")
            if let first = await flight(
                "OSL",
                "HEL",
                on: "2024-04-01",
                departs: "07:05",
                arrives: "09:50",
                airline: "Finnair",
                number: "AY912",
                aircraft: "Airbus A321"
            ),
                let second = await flight(
                    "HEL",
                    "HND",
                    on: "2024-04-01",
                    departs: "17:25",
                    arrives: "2024-04-02T14:55",
                    actualArrival: "2024-04-02T15:20",
                    airline: "Finnair",
                    number: "AY61",
                    aircraft: "Airbus A350-900"
                ) {
                try logJourney(legs: [first, second], tripID: japan.id)
            }
            try await visit(
                "Tokyo",
                .city,
                span("2024-04-02", "2024-04-06"),
                trip: japan,
                rating: 5
            )
            try await visit("Sensō-ji", .landmark, day("2024-04-03"), .dayTrip, trip: japan)
            try await visit("Meiji Jingū", .landmark, day("2024-04-04"), .dayTrip, trip: japan)
            if let train = await ground(
                .rail,
                "Tokyo",
                "Kyoto",
                on: "2024-04-07",
                departs: "08:03",
                arrives: "10:18",
                operatorName: "JR Central",
                travelClass: "Standard"
            ) {
                try logJourney(legs: [train], tripID: japan.id)
            }
            try await visit(
                "Kyoto",
                .city,
                span("2024-04-07", "2024-04-10"),
                trip: japan,
                rating: 5
            )
            try await visit(
                "Fushimi Inari-taisha",
                .landmark,
                day("2024-04-08"),
                .dayTrip,
                trip: japan
            )
            try await visit(
                "Kinkaku-ji Temple",
                .landmark,
                day("2024-04-09"),
                .dayTrip,
                trip: japan
            )
            try await visit("Osaka", .city, day("2024-04-10"), .dayTrip, trip: japan)
            if let home = await flight(
                "KIX",
                "HEL",
                on: "2024-04-11",
                departs: "10:35",
                arrives: "15:25",
                airline: "Finnair",
                number: "AY78",
                aircraft: "Airbus A350-900"
            ),
                let last = await flight(
                    "HEL",
                    "OSL",
                    on: "2024-04-11",
                    departs: "17:10",
                    arrives: "17:55",
                    actualArrival: "18:20",
                    airline: "Finnair",
                    number: "AY915",
                    aircraft: "Airbus A320"
                ) {
                try logJourney(legs: [home, last], tripID: japan.id)
            }

            // Italy, autumn 2023.
            let italy = try trip("Rome, Florence, Venice")
            if let out = await flight(
                "OSL",
                "FCO",
                on: "2023-09-14",
                departs: "10:20",
                arrives: "13:55",
                actualArrival: "14:40",
                airline: "Norwegian",
                number: "D84718",
                aircraft: "Boeing 737-800"
            ) {
                try logJourney(legs: [out], tripID: italy.id)
            }
            try await visit("Rome", .city, span("2023-09-14", "2023-09-18"), trip: italy, rating: 5)
            try await visit("Colosseum", .landmark, day("2023-09-15"), .dayTrip, trip: italy)
            try await visit("Pantheon", .landmark, day("2023-09-15"), .dayTrip, trip: italy)
            try await visit("Roman Forum", .landmark, day("2023-09-15"), .dayTrip, trip: italy)
            try await visit(
                "St. Peter's Basilica",
                .landmark,
                day("2023-09-16"),
                .dayTrip,
                trip: italy
            )
            try await visit("Sistine Chapel", .landmark, day("2023-09-16"), .dayTrip, trip: italy)
            if let train = await ground(
                .rail,
                "Rome",
                "Florence",
                on: "2023-09-18",
                departs: "09:10",
                arrives: "10:42",
                operatorName: "Trenitalia",
                travelClass: "First"
            ) {
                try logJourney(legs: [train], tripID: italy.id)
            }
            try await visit("Florence", .city, span("2023-09-18", "2023-09-21"), trip: italy)
            try await visit(
                "Florence Cathedral",
                .landmark,
                day("2023-09-19"),
                .dayTrip,
                trip: italy
            )
            try await visit("Uffizi Gallery", .landmark, day("2023-09-19"), .dayTrip, trip: italy)
            try await visit("Ponte Vecchio", .landmark, day("2023-09-20"), .dayTrip, trip: italy)
            if let train = await ground(
                .rail,
                "Florence",
                "Venice",
                on: "2023-09-21",
                departs: "11:05",
                arrives: "13:10",
                operatorName: "Italo",
                travelClass: "Standard"
            ) {
                try logJourney(legs: [train], tripID: italy.id)
            }
            try await visit(
                "Venice",
                .city,
                span("2023-09-21", "2023-09-24"),
                trip: italy,
                rating: 4
            )
            try await visit(
                "St Mark's Basilica",
                .landmark,
                day("2023-09-22"),
                .dayTrip,
                trip: italy
            )
            try await visit("Doge's Palace", .landmark, day("2023-09-22"), .dayTrip, trip: italy)
            if let back = await flight(
                "VCE",
                "OSL",
                on: "2023-09-24",
                departs: "15:40",
                arrives: "18:25",
                airline: "SAS",
                number: "SK4710",
                aircraft: "Airbus A320neo"
            ) {
                try logJourney(legs: [back], tripID: italy.id)
            }

            // Norway in a nutshell, 2022.
            let fjords = try trip("Fjords by rail and road")
            if let train = await ground(
                .rail,
                "Oslo",
                "Bergen",
                on: "2022-07-08",
                departs: "08:25",
                arrives: "15:22",
                operatorName: "Vy",
                travelClass: "Standard",
                route: 1
            ) {
                try logJourney(legs: [train], tripID: fjords.id)
            }
            try await visit(
                "Bergen",
                .city,
                span("2022-07-08", "2022-07-11"),
                trip: fjords,
                rating: 4
            )
            try await visit("Bryggen", .landmark, day("2022-07-09"), .dayTrip, trip: fjords)
            if let drive = await ground(.roadTrip, "Bergen", "Ålesund", on: "2022-07-11") {
                try logJourney(legs: [drive], tripID: fjords.id)
            }
            try await visit(
                "Geirangerfjord",
                .landmark,
                day("2022-07-12"),
                .dayTrip,
                trip: fjords,
                rating: 5
            )
            try await visit("Ålesund", .city, span("2022-07-11", "2022-07-13"), trip: fjords)
            try await visit("Tromsø", .city, span("2022-12-27", "2022-12-30"), trip: nil, rating: 5)

            // New York, 2019.
            let newYork = try trip("New York")
            if let out = await flight(
                "OSL",
                "JFK",
                on: "2019-10-20",
                departs: "16:15",
                arrives: "18:35",
                actualArrival: "18:28",
                airline: "SAS",
                number: "SK909",
                aircraft: "Airbus A330-300",
                travelClass: "Premium economy"
            ) {
                try logJourney(legs: [out], tripID: newYork.id)
            }
            try await visit(
                "New York City",
                .city,
                span("2019-10-20", "2019-10-26"),
                trip: newYork,
                rating: 5
            )
            try await visit(
                "Statue of Liberty",
                .landmark,
                day("2019-10-21"),
                .dayTrip,
                trip: newYork
            )
            try await visit("Central Park", .landmark, day("2019-10-22"), .dayTrip, trip: newYork)
            try await visit(
                "Metropolitan Museum of Art",
                .landmark,
                day("2019-10-22"),
                .dayTrip,
                trip: newYork
            )
            try await visit(
                "Empire State Building",
                .landmark,
                day("2019-10-23"),
                .dayTrip,
                trip: newYork
            )
            if let back = await flight(
                "JFK",
                "OSL",
                on: "2019-10-26",
                departs: "18:10",
                arrives: "2019-10-27T07:45",
                airline: "SAS",
                number: "SK910",
                aircraft: "Airbus A330-300"
            ) {
                try logJourney(legs: [back], tripID: newYork.id)
            }

            // Australia, 2018.
            let australia = try trip("Sydney and the Blue Mountains")
            if let first = await flight(
                "OSL",
                "DXB",
                on: "2018-02-03",
                departs: "15:00",
                arrives: "23:59",
                airline: "Emirates",
                number: "EK160",
                aircraft: "Boeing 777-300ER"
            ),
                let second = await flight(
                    "DXB",
                    "SYD",
                    on: "2018-02-04",
                    departs: "02:15",
                    arrives: "22:15",
                    airline: "Emirates",
                    number: "EK414",
                    aircraft: "Airbus A380"
                ) {
                try logJourney(legs: [first, second], tripID: australia.id)
            }
            try await visit(
                "Sydney",
                .city,
                span("2018-02-04", "2018-02-14"),
                trip: australia,
                rating: 5
            )
            try await visit(
                "Sydney Opera House",
                .landmark,
                day("2018-02-05"),
                .dayTrip,
                trip: australia
            )
            try await visit(
                "Sydney Harbour Bridge",
                .landmark,
                day("2018-02-05"),
                .dayTrip,
                trip: australia
            )
            try await visit("Katoomba", .city, day("2018-02-08"), .dayTrip, trip: australia)
            try await visit("Dubai", .city, day("2018-02-04"), .layover, trip: australia)

            // Odds and ends, not in any trip.
            try await visit("Stockholm", .city, day("2021-08-14"), .dayTrip, trip: nil)
            try await visit("Copenhagen", .city, .month(year: 2020, month: 5), .stayed, trip: nil)
            try await visit("Reykjavík", .city, .year(2017), .stayed, trip: nil)
            try await visit("Paris", .city, .unknown, .stayed, trip: nil)
            try await visit("Eiffel Tower", .landmark, .unknown, .dayTrip, trip: nil)
            try await visit("Helsinki", .city, day("2024-04-01"), .layover, trip: nil)

            // A wishlist.
            for (name, kind) in [
                ("Machu Picchu", PlaceKind.landmark),
                ("Torres del Paine National Park", .landmark),
                ("Petra", .landmark),
                ("Reykjavík", .city),
            ] {
                if let place = await place(name, kind) {
                    addToWishlist(place)
                }
            }
            if let siberian = route(id: 8) {
                addToWishlist(route: siberian)
            }

            try await seedSampleTransit(japan: japan.id, italy: italy.id)
        }
        // swiftlint:enable cyclomatic_complexity function_body_length
    }
#endif
