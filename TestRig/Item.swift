//
//  Item.swift
//  TestRig
//
//  Created by Martin Westhead on 8/17/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
