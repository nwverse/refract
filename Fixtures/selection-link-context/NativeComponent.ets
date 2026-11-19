@ObservedV2
export class RefractSelectionRange {
  @Trace public var start: number
  @Trace public var end: number
  constructor(start: number, end: number) {
    this.start = start
    this.end = end
  }
}

@ObservedV2
export class RefractSelectionLink {
  @Trace public var range: RefractSelectionRange
  @Trace public var destination: string
  constructor(range: RefractSelectionRange, destination: string) {
    this.range = range
    this.destination = destination
  }
}

@ObservedV2
export class RefractSelectionContext {
  @Trace public var text: string
  @Trace public var range: RefractSelectionRange
  constructor(text: string, range: RefractSelectionRange) {
    this.text = text
    this.range = range
  }
}

@ObservedV2
export class RefractSelectionContent {
  @Trace public var text: string
  @Trace public var links: RefractSelectionLink[]
  constructor(text: string, links: RefractSelectionLink[]) {
    this.text = text
    this.links = links
  }
}

@ComponentV2
export struct NativeSelectionMessage {
  @Param @Require public var content: RefractSelectionContent
  @Param @Require public var onLink: (destination: string) => void
  @Param @Require public var onUseAsContext: (context: RefractSelectionContext) => void
  @Param @Require public var onEditWithAI: (context: RefractSelectionContext) => void

  build() {
    Text(this.content.text)
      // The production app attaches its native selection and explicit actions here.
  }
}
