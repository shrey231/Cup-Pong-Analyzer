//
//  GameManager.swift
//  Pong
//
//  Created by Shreyas Vaderiyattil on 11/25/21.
//

import Foundation
import GameKit

class GameManager {
    
    class State: GKState {
        private(set) var validNextStates: [State.Type]
        
        init(_ validNextStates: [State.Type]) {
            self.validNextStates = validNextStates
            super.init()
        }
        
        func addValidNextState(_ state: State.Type) {
            validNextStates.append(state)
        }
        
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return validNextStates.contains(where: { stateClass == $0 })
        }
        
        override func didEnter(from previousState: GKState?) {
            let note = GameStateChangeNotification(newState: self, previousState: previousState as? State)
            note.post()
        }
    }
    
    class InactiveState: State {
    }
    
    class SetupCameraState: State {
    }
    
    class DetectingCupState: State {
    }
    
    class DetectedCupState: State {
    }

    class DetectingPlayerState: State {
    }
    
    class DetectedPlayerState: State {
    }

    class TrackThrowsState: State {
    }
    
    class ThrowCompletedState: State {
    }

    class ShowSummaryState: State {
    }

    var activeObservers = [UIViewController: NSObjectProtocol]()
    
    let stateMachine: GKStateMachine
    var cupRegion = CGRect.null
    var holeRegion = CGRect.null
    var recordedVideoSource: AVAsset?
    var playerStats = PlayerStats()
    var lastThrowMetrics = ThrowMetrics()
    var pointToMeterMultiplier = Double.nan
    var previewImage = UIImage()
    
    static var shared = GameManager()
    
    private init() {
        let states = [
            InactiveState([SetupCameraState.self]),
            SetupCameraState([DetectingCupState.self]),
            DetectingCupState([DetectedCupState.self]),
            DetectedCupState([DetectingPlayerState.self]),
            DetectingPlayerState([DetectedPlayerState.self]),
            DetectedPlayerState([TrackThrowsState.self]),
            TrackThrowsState([ThrowCompletedState.self, ShowSummaryState.self]),
            ThrowCompletedState([ShowSummaryState.self, TrackThrowsState.self]),
            ShowSummaryState([DetectingPlayerState.self])
        ]
        for state in states where !(state is InactiveState) {
            state.addValidNextState(InactiveState.self)
        }
        stateMachine = GKStateMachine(states: states)
    }
    
    func reset() {
        cupRegion = .null
        recordedVideoSource = nil
        playerStats = PlayerStats()
        pointToMeterMultiplier = .nan
        let notificationCenter = NotificationCenter.default
        for observer in activeObservers {
            notificationCenter.removeObserver(observer)
        }
        activeObservers.removeAll()
        stateMachine.enter(InactiveState.self)
    }
}

protocol GameStateChangeObserver: AnyObject {
    func gameManagerDidEnter(state: GameManager.State, from previousState: GameManager.State?)
}

extension GameStateChangeObserver where Self: UIViewController {
    func startObservingStateChanges() {
        let token = NotificationCenter.default.addObserver(forName: GameStateChangeNotification.name, object: GameStateChangeNotification.object,
               queue: nil) { [weak self] (notification) in
            let note = GameStateChangeNotification(notification: notification)
            if note != GameStateChangeNotification(notification: notification) {
                return
            }
            self?.gameManagerDidEnter(state: note!.newState, from: note!.previousState)
        }
        let gameManager = GameManager.shared
        gameManager.activeObservers[self] = token
    }
    
    func stopObservingStateChanges() {
        let gameManager = GameManager.shared
        let token = gameManager.activeObservers[self]
        if token == nil {
            return
        }
        NotificationCenter.default.removeObserver(token)
        gameManager.activeObservers.removeValue(forKey: self)
    }
}

struct GameStateChangeNotification: Equatable {
    static let name = NSNotification.Name("GameStateChangeNotification")
    static let object = GameManager.shared
    
    let newStateKey = "newState"
    let previousStateKey = "previousState"

    let newState: GameManager.State
    let previousState: GameManager.State?
    
    init(newState: GameManager.State, previousState: GameManager.State?) {
        self.newState = newState
        self.previousState = previousState
    }
    
    init?(notification: Notification) {
        let newState = notification.userInfo?[newStateKey] as? GameManager.State
        if notification.name != Self.name {
            return nil
        }
        self.newState = newState!
        self.previousState = notification.userInfo?[previousStateKey] as? GameManager.State
    }
    
    func post() {
        var userInfo = [newStateKey: newState]
        if let previousState = previousState {
            userInfo[previousStateKey] = previousState
        }
        NotificationCenter.default.post(name: Self.name, object: Self.object, userInfo: userInfo)
    }
}

typealias GameStateChangeObserverViewController = UIViewController & GameStateChangeObserver
