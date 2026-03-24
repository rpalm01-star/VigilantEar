//
//  UIManager.swift
//  VigilantEar
//
//  Created by Robert Palmer on 5/4/26.
//
import Combine

@MainActor
class UIManager: ObservableObject {
    @Published var isMenuOpen: Bool = false
}
