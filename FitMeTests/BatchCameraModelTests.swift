import Foundation
import Testing
@testable import FitMe

@MainActor
struct BatchCameraModelTests {
    @Test func shotsAreKeptInOrderAndHandedOverAsLoaders() async {
        let model = BatchCameraModel(camera: FakeCamera())
        await model.start()
        #expect(model.state == .ready)

        await model.shoot()
        await model.shoot()
        await model.shoot()

        #expect(model.shots == [Data([1]), Data([2]), Data([3])])
        var loaded: [Data?] = []
        for load in model.loaders {
            await loaded.append(load())
        }
        #expect(loaded == [Data([1]), Data([2]), Data([3])])
    }

    @Test func removingTheLastShotKeepsTheRest() async {
        let model = BatchCameraModel(camera: FakeCamera())
        await model.start()
        await model.shoot()
        await model.shoot()

        model.undoLastShot()

        #expect(model.shots == [Data([1])])
    }

    @Test func asksForAccessOnceAndExplainsARefusal() async {
        let camera = FakeCamera(access: .notAsked, grantsOnRequest: false)
        let model = BatchCameraModel(camera: camera)

        await model.start()

        #expect(model.state == .denied)
        #expect(!camera.isRunning)
        await model.shoot()
        #expect(model.shots.isEmpty)
    }

    @Test func aDeviceWithoutACameraSaysSo() async {
        let model = BatchCameraModel(camera: FakeCamera(hasCamera: false))
        await model.start()
        #expect(model.state == .unavailable)
        #expect(!model.canShoot)
    }

    @Test func aFailedShotIsReportedAndNotKept() async {
        let model = BatchCameraModel(camera: FakeCamera(failing: true))
        await model.start()

        await model.shoot()

        #expect(model.shots.isEmpty)
        #expect(model.errorMessage != nil)
    }

    @Test func aBatchStopsAtItsLimit() async {
        let model = BatchCameraModel(camera: FakeCamera())
        await model.start()
        for _ in 0 ..< BatchCameraModel.maxShots + 2 {
            await model.shoot()
        }
        #expect(model.shots.count == BatchCameraModel.maxShots)
        #expect(!model.canShoot)
    }

    @Test func stoppingStopsTheCamera() async {
        let camera = FakeCamera()
        let model = BatchCameraModel(camera: camera)
        await model.start()
        #expect(camera.isRunning)
        await model.stop()
        #expect(!camera.isRunning)
    }
}
