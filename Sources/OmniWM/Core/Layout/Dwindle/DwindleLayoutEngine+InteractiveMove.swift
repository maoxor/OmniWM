// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

struct DwindleInteractiveMove {
    let token: WindowToken
    let workspaceId: WorkspaceDescriptor.ID
    let startLocation: CGPoint
    var targetToken: WindowToken?
    var dropDirection: Direction?
}

enum DwindleDropZone {
    static let centerFraction: CGFloat = 0.4

    static func direction(for point: CGPoint, in frame: CGRect) -> Direction? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let px = (point.x - frame.minX) / frame.width
        let py = (point.y - frame.minY) / frame.height
        let inset = (1 - centerFraction) / 2
        if px > inset, px < 1 - inset, py > inset, py < 1 - inset { return nil }
        let distances: [(Direction, CGFloat)] = [(.left, px), (.right, 1 - px), (.down, py), (.up, 1 - py)]
        return distances.min { $0.1 < $1.1 }?.0
    }
}

extension DwindleLayoutEngine {
    func interactiveMoveBegin(
        token: WindowToken,
        startLocation: CGPoint,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        guard interactiveResize == nil,
              interactiveMove == nil,
              let leaf = findNode(for: token, in: workspaceId),
              leaf.isLeaf,
              !isWindowFullscreen(token, in: workspaceId)
        else { return false }
        interactiveMove = DwindleInteractiveMove(token: token, workspaceId: workspaceId, startLocation: startLocation)
        return true
    }

    func interactiveMoveUpdate(currentLocation: CGPoint, at time: TimeInterval) -> WindowToken? {
        guard let move = interactiveMove else { return nil }
        guard let source = findNode(for: move.token, in: move.workspaceId) else {
            interactiveMoveCancel()
            return nil
        }
        let target = hitTestFocusableWindow(point: currentLocation, in: move.workspaceId, at: time)
            .flatMap { candidate -> WindowToken? in
                guard let node = findNode(for: candidate, in: move.workspaceId),
                      node !== source,
                      !isWindowFullscreen(candidate, in: move.workspaceId)
                else { return nil }
                return candidate
            }
        interactiveMove?.targetToken = target
        interactiveMove?.dropDirection = target
            .flatMap { findNode(for: $0, in: move.workspaceId)?.presentedFrame(at: time) }
            .flatMap { DwindleDropZone.direction(for: currentLocation, in: $0) }
        return target
    }

    @discardableResult
    func interactiveMoveEnd() -> WindowToken? {
        guard let move = interactiveMove else { return nil }
        interactiveMove = nil
        guard let targetToken = move.targetToken else { return nil }
        if let direction = move.dropDirection,
           insert(move.token, beside: targetToken, direction: direction, in: move.workspaceId)
        {
            return targetToken
        }
        guard swapLeafTiles(of: move.token, and: targetToken, in: move.workspaceId) else { return nil }
        return targetToken
    }

    /// Drop near an edge of the target: take the window out of the tree (its sibling absorbs the
    /// freed space) and split the target on that side, as a preselected insertion would.
    func insert(
        _ token: WindowToken,
        beside targetToken: WindowToken,
        direction: Direction,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        guard token != targetToken,
              let state = existingState(for: workspaceId),
              findNode(for: token, in: workspaceId) != nil,
              findNode(for: targetToken, in: workspaceId) != nil
        else { return false }
        let targetFrame = findNode(for: targetToken, in: workspaceId)?.cachedFrame
        removeWindow(token: token, from: workspaceId)
        guard let targetLeaf = findNode(for: targetToken, in: workspaceId) else { return false }
        state.selectedNodeId = targetLeaf.id
        state.preselection = direction
        addWindow(token: token, to: workspaceId, activeWindowFrame: targetFrame)
        return findNode(for: token, in: workspaceId) != nil
    }

    func interactiveMoveCancel() {
        interactiveMove = nil
    }
}
