import SwiftUI

/// Public module boundary for the recovery page. Selection is controlled by the caller.
/// No persistence, HealthKit, network, model inference or recovery calculation happens here.
struct BodyMapView: View {
  let presentation: BodyMapPresentation
  let onSelect: (MuscleID) -> Void
  var constrainedPolicy: BodyMapDisplayPolicy? = nil

  var body: some View {
    BodyMapRendererView(
      input: BodyMapRenderInput(presentation: presentation), onSelect: onSelect,
      constrainedPolicy: constrainedPolicy)
  }
}
