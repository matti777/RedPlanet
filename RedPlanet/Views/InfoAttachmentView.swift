//
//  InfoAttachmentView.swift
//  RedPlanet
//
//  Created by Matti Dahlbom on 30.3.2024.
//

import SwiftUI

struct InfoAttachmentView: View {
    @Binding var text: String
    @Binding var show: Bool
    
    var body: some View {
        VStack {
            Text(text)
                .padding(20)

            Button {
                withAnimation(.easeIn) {
                    show = false
                }
            } label: {
                Text("Close")
            }
            .padding(20)
        }
    }
}

#Preview(windowStyle: .automatic, traits: .fixedLayout(width: 300, height: 180)) {
    InfoAttachmentView(text: .constant("Generating geometry.."), show: .constant(true))
}
