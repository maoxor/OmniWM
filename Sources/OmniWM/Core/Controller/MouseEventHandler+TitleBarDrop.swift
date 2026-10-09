// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

extension MouseEventHandler {
    @discardableResult
    func dropNativeTitleBarDragOnDwindleTile(at location: CGPoint) -> Bool {
        guard let controller,
              let drag = state.nativeTitleBarDrag,
              drag.phase != .armed,
              let entry = controller.workspaceManager.entry(for: drag.token),
              entry.mode == .tiling,
              let engine = controller.dwindleEngine,
              engine.findNode(for: drag.token, in: entry.workspaceId) != nil,
              engine.interactiveMoveBegin(token: drag.token, startLocation: location, in: entry.workspaceId)
        else { return false }
        let wsId = entry.workspaceId
        guard engine.interactiveMoveUpdate(currentLocation: location, at: controller.animationClock.now()) != nil else {
            engine.interactiveMoveCancel()
            return false
        }
        let moved = controller.workspaceManager.withEngineMutationScope(
            in: wsId,
            label: "dwindle_titlebar_drop",
            source: .mouse
        ) {
            engine.interactiveMoveEnd() != nil
        }
        guard moved else { return false }
        controller.workspaceManager.recordLayoutOperation(.windowsSwapped, in: wsId, source: .mouse)
        retireNativeTitleBarDragAtInputBoundary()
        if controller.hasStartedServices {
            controller.layoutRefreshController.requestImmediateRelayout(reason: .interactiveGesture)
        }
        return true
    }
}
