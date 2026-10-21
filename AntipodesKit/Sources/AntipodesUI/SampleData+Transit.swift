#if DEBUG
    import AntipodesCore
    import Foundation

    /// City transit rides for the sample log: real lines and stops from the bundled
    /// packs, so the transit statistics have something to show (R-JLOG-5, R-TRAN-3).
    extension AppModel {
        func seedSampleTransit(japan: UUID, italy: UUID) async throws {
            let rides = [
                SampleRide("Tokyo subway", "Ginza Line", "Asakusa", "Shibuya", "2024-04-03", japan),
                SampleRide(
                    "Tokyo subway", "Marunouchi Line", "Tokyo Station", "Shinjuku", "2024-04-05",
                    japan
                ),
                SampleRide("Osaka Metro", "Midōsuji Line", "Umeda", "Namba", "2024-04-10", japan),
                SampleRide("Rome Metro", "Line A", "Termini", "Ottaviano", "2023-09-16", italy),
            ]
            for ride in rides {
                guard let leg = await sampleRide(
                    system: ride.system,
                    line: ride.line,
                    from: ride.from,
                    to: ride.to,
                    on: ride.date
                ) else { continue }
                try logJourney(legs: [leg], tripID: ride.trip)
            }
        }

        private func sampleRide(
            system name: String,
            line lineName: String,
            from: String,
            to: String,
            on date: String
        ) async -> JourneyLeg? {
            guard let places,
                  let system = try? await places.transitSystems().first(where: { $0.name == name }),
                  let network = try? await places.transitNetwork(systems: [system.id]),
                  let line = network.lines.values.first(where: {
                      $0.systemID == system.id && $0.name == lineName
                  })
            else { return nil }
            let stops = network.orderedStops(ofLine: line.id)
            func stop(named stopName: String) -> Int64? {
                stops.first { network.stops[$0]?.name == stopName }
            }
            guard let boarding = stop(named: from),
                  let alighting = stop(named: to),
                  let origin = try? await places.transitStopPlace(id: boarding),
                  let destination = try? await places.transitStopPlace(id: alighting)
            else { return nil }
            let path = network.route(onLine: line.id, from: boarding, to: alighting)
            return JourneyLeg(
                mode: .cityTransit,
                origin: origin,
                destination: destination,
                date: CalendarDate(iso: date).map(FlexibleDate.day) ?? .unknown,
                storedPathLengthKm: path.flatMap(network.lengthKm(of:)),
                transitLineID: line.id,
                networkVersion: system.networkVersion,
                serviceNumber: line.shortName ?? line.name
            )
        }
    }

    private struct SampleRide {
        let system: String
        let line: String
        let from: String
        let to: String
        let date: String
        let trip: UUID

        init(
            _ system: String,
            _ line: String,
            _ from: String,
            _ to: String,
            _ date: String,
            _ trip: UUID
        ) {
            self.system = system
            self.line = line
            self.from = from
            self.to = to
            self.date = date
            self.trip = trip
        }
    }
#endif
