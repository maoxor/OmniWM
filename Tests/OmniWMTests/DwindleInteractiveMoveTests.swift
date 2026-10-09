// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

final class DwindleInteractiveMoveTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private struct Fixture {
        let engine: DwindleLayoutEngine
        let ws: WorkspaceDescriptor.ID
        let a: WindowToken
        let b: WindowToken

        func frame(_ token: WindowToken) -> CGRect? {
            engine.presentedFrame(for: token, in: ws, at: 0)
        }

        func nodeFrame(_ token: WindowToken) -> CGRect? {
            engine.findNode(for: token, in: ws)?.cachedFrame
        }
    }

    private func makeFixture() throws -> Fixture {
        let engine = DwindleLayoutEngine()
        let ws = WorkspaceDescriptor.ID()
        let a = WindowToken(pid: 1, windowId: 1)
        let b = WindowToken(pid: 2, windowId: 2)
        _ = engine.addWindow(token: a, to: ws, activeWindowFrame: nil)
        _ = engine.addWindow(token: b, to: ws, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: ws, screen: screen)
        let fixture = Fixture(engine: engine, ws: ws, a: a, b: b)
        XCTAssertNotNil(fixture.frame(a))
        XCTAssertNotNil(fixture.frame(b))
        return fixture
    }

    func testBeginRejectsUnknownFullscreenAndBusyStates() throws {
        let fixture = try makeFixture()
        let engine = fixture.engine

        XCTAssertFalse(engine.interactiveMoveBegin(
            token: WindowToken(pid: 9, windowId: 9),
            startLocation: .zero,
            in: fixture.ws
        ))

        XCTAssertTrue(engine.interactiveResizeBegin(
            token: fixture.a,
            edges: [.right],
            startLocation: .zero,
            in: fixture.ws,
            innerGap: 0
        ))
        XCTAssertFalse(engine.interactiveMoveBegin(token: fixture.a, startLocation: .zero, in: fixture.ws))
        engine.interactiveResizeEnd()

        engine.setSelectedNode(engine.findNode(for: fixture.b, in: fixture.ws), in: fixture.ws)
        XCTAssertEqual(engine.toggleFullscreen(in: fixture.ws), fixture.b)
        XCTAssertFalse(engine.interactiveMoveBegin(token: fixture.b, startLocation: .zero, in: fixture.ws))

        XCTAssertTrue(engine.interactiveMoveBegin(token: fixture.a, startLocation: .zero, in: fixture.ws))
        XCTAssertFalse(engine.interactiveMoveBegin(token: fixture.a, startLocation: .zero, in: fixture.ws))
        let fullscreenCenter = try XCTUnwrap(fixture.frame(fixture.b)).center
        XCTAssertNil(engine.interactiveMoveUpdate(currentLocation: fullscreenCenter, at: 0))
        XCTAssertFalse(engine.interactiveMoveEnd() != nil)
    }

    func testUpdateReturnsTargetOnlyOverAnotherTile() throws {
        let fixture = try makeFixture()
        let engine = fixture.engine
        let aCenter = try XCTUnwrap(fixture.frame(fixture.a)).center
        let bCenter = try XCTUnwrap(fixture.frame(fixture.b)).center

        XCTAssertTrue(engine.interactiveMoveBegin(token: fixture.a, startLocation: aCenter, in: fixture.ws))
        XCTAssertNil(engine.interactiveMoveUpdate(currentLocation: aCenter, at: 0))
        XCTAssertNil(engine.interactiveMove?.targetToken)
        XCTAssertEqual(engine.interactiveMoveUpdate(currentLocation: bCenter, at: 0), fixture.b)
        XCTAssertEqual(engine.interactiveMove?.targetToken, fixture.b)
        XCTAssertNil(engine.interactiveMoveUpdate(currentLocation: CGPoint(x: -50, y: -50), at: 0))
        XCTAssertNil(engine.interactiveMove?.targetToken)
    }

    func testEndSwapsTilesAndRekeysAllGroupMembers() throws {
        let fixture = try makeFixture()
        let engine = fixture.engine
        let c = WindowToken(pid: 3, windowId: 3)
        _ = engine.addWindow(token: c, to: fixture.ws, activeWindowFrame: nil)
        XCTAssertTrue(engine.groupWindow(c, into: fixture.b, in: fixture.ws))
        _ = engine.calculateLayout(for: fixture.ws, screen: screen)
        let aFrame = try XCTUnwrap(fixture.nodeFrame(fixture.a))
        let groupFrame = try XCTUnwrap(fixture.nodeFrame(c))
        let groupCenter = try XCTUnwrap(fixture.frame(c)).center
        XCTAssertTrue(engine.findNode(for: fixture.b, in: fixture.ws) === engine.findNode(for: c, in: fixture.ws))

        XCTAssertTrue(engine.interactiveMoveBegin(token: fixture.a, startLocation: aFrame.center, in: fixture.ws))
        XCTAssertEqual(engine.interactiveMoveUpdate(currentLocation: groupCenter, at: 0), c)
        XCTAssertEqual(engine.interactiveMoveEnd(), c)

        XCTAssertNil(engine.interactiveMove)
        _ = engine.calculateLayout(for: fixture.ws, screen: screen)
        XCTAssertEqual(fixture.nodeFrame(fixture.a), groupFrame)
        XCTAssertEqual(fixture.nodeFrame(fixture.b), aFrame)
        XCTAssertEqual(fixture.nodeFrame(c), aFrame)
        let groupNode = try XCTUnwrap(engine.findNode(for: fixture.b, in: fixture.ws))
        XCTAssertTrue(groupNode === engine.findNode(for: c, in: fixture.ws))
        XCTAssertEqual(groupNode.tile?.members.map(\.token), [fixture.b, c])
        XCTAssertTrue(engine.selectedNode(in: fixture.ws) === engine.findNode(for: fixture.a, in: fixture.ws))
    }

    func testEndWithoutTargetDoesNotMutate() throws {
        let fixture = try makeFixture()
        let engine = fixture.engine
        let aFrame = try XCTUnwrap(fixture.frame(fixture.a))
        let bFrame = try XCTUnwrap(fixture.frame(fixture.b))

        XCTAssertTrue(engine.interactiveMoveBegin(token: fixture.a, startLocation: aFrame.center, in: fixture.ws))
        XCTAssertNil(engine.interactiveMoveUpdate(currentLocation: aFrame.center, at: 0))
        XCTAssertNil(engine.interactiveMoveEnd())

        XCTAssertNil(engine.interactiveMove)
        _ = engine.calculateLayout(for: fixture.ws, screen: screen)
        XCTAssertEqual(fixture.frame(fixture.a), aFrame)
        XCTAssertEqual(fixture.frame(fixture.b), bFrame)
    }

    func testRemovedWindowsAbortTheGesture() throws {
        let fixture = try makeFixture()
        let engine = fixture.engine
        let aFrame = try XCTUnwrap(fixture.frame(fixture.a))
        let bFrame = try XCTUnwrap(fixture.frame(fixture.b))

        XCTAssertTrue(engine.interactiveMoveBegin(token: fixture.a, startLocation: aFrame.center, in: fixture.ws))
        XCTAssertEqual(engine.interactiveMoveUpdate(currentLocation: bFrame.center, at: 0), fixture.b)
        engine.removeWindow(token: fixture.b, from: fixture.ws)
        XCTAssertNil(engine.interactiveMoveEnd())
        XCTAssertNil(engine.interactiveMove)

        let second = try makeFixture()
        XCTAssertTrue(second.engine.interactiveMoveBegin(token: second.a, startLocation: .zero, in: second.ws))
        second.engine.removeWindow(token: second.a, from: second.ws)
        XCTAssertNil(second.engine.interactiveMoveUpdate(currentLocation: bFrame.center, at: 0))
        XCTAssertNil(second.engine.interactiveMove)
    }

    func testCancelAndLayoutRemovalClearTheSession() throws {
        let fixture = try makeFixture()
        let engine = fixture.engine

        XCTAssertTrue(engine.interactiveMoveBegin(token: fixture.a, startLocation: .zero, in: fixture.ws))
        engine.interactiveMoveCancel()
        XCTAssertNil(engine.interactiveMove)

        XCTAssertTrue(engine.interactiveMoveBegin(token: fixture.a, startLocation: .zero, in: fixture.ws))
        engine.removeLayout(for: fixture.ws)
        XCTAssertNil(engine.interactiveMove)
    }

    func testDropZoneCenterSwapsAndEdgesPickNearestSide() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 200)
        XCTAssertNil(DwindleDropZone.direction(for: CGPoint(x: 300, y: 200), in: frame))
        XCTAssertEqual(DwindleDropZone.direction(for: CGPoint(x: 110, y: 200), in: frame), .left)
        XCTAssertEqual(DwindleDropZone.direction(for: CGPoint(x: 490, y: 200), in: frame), .right)
        XCTAssertEqual(DwindleDropZone.direction(for: CGPoint(x: 300, y: 105), in: frame), .down)
        XCTAssertEqual(DwindleDropZone.direction(for: CGPoint(x: 300, y: 295), in: frame), .up)
    }

    func testEdgeDropInsertsBesideTargetAndReflowsWithoutGapsOrOverlap() throws {
        let fixture = try makeFixture()
        let engine = fixture.engine
        let c = WindowToken(pid: 3, windowId: 3)
        _ = engine.addWindow(token: c, to: fixture.ws, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: fixture.ws, screen: screen)
        let aFrame = try XCTUnwrap(fixture.nodeFrame(fixture.a))
        let cFrame = try XCTUnwrap(fixture.nodeFrame(c))
        let dropPoint = CGPoint(x: aFrame.minX + 5, y: aFrame.midY)
        let areaBefore = try [fixture.a, fixture.b, c].map { try XCTUnwrap(fixture.nodeFrame($0)) }
            .reduce(0) { $0 + $1.width * $1.height }

        XCTAssertTrue(engine.interactiveMoveBegin(token: c, startLocation: cFrame.center, in: fixture.ws))
        XCTAssertEqual(engine.interactiveMoveUpdate(currentLocation: dropPoint, at: 0), fixture.a)
        XCTAssertEqual(engine.interactiveMove?.dropDirection, .left)
        XCTAssertEqual(engine.interactiveMoveEnd(), fixture.a)
        _ = engine.calculateLayout(for: fixture.ws, screen: screen)

        let frames = try [fixture.a, fixture.b, c].map { try XCTUnwrap(fixture.nodeFrame($0)) }
        XCTAssertLessThan(frames[2].midX, frames[0].midX)
        XCTAssertEqual(frames.reduce(0) { $0 + $1.width * $1.height }, areaBefore, accuracy: areaBefore * 0.01)
        for i in 0 ..< frames.count {
            for j in i + 1 ..< frames.count {
                let overlap = frames[i].intersection(frames[j])
                XCTAssertLessThanOrEqual(overlap.isNull ? 0 : overlap.width * overlap.height, 0.5)
            }
        }
    }
}
