@Entry
@Component
struct OverlayGlow {
  @State breathe: number = 0.5;

  aboutToAppear(): void {
    this.getUIContext().animateTo({ duration: 1600, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.breathe = 1;
    });
  }

  @Builder
  edge(vertical: boolean, align: Alignment) {
    Row()
      .width(vertical ? 4 : '100%')
      .height(vertical ? '100%' : 4)
      .linearGradient({
        angle: vertical ? 180 : 90,
        colors: [[$r('app.color.orb_teal'), 0], [$r('app.color.orb_violet'), 0.5], [$r('app.color.orb_coral'), 1]]
      })
      .align(align)
  }

  build() {
    Stack() {
      Column() {
        this.edge(false, Alignment.Top)
      }.width('100%').height('100%').justifyContent(FlexAlign.Start)
      Column() {
        this.edge(false, Alignment.Bottom)
      }.width('100%').height('100%').justifyContent(FlexAlign.End)
      Row() {
        this.edge(true, Alignment.Start)
      }.width('100%').height('100%').justifyContent(FlexAlign.Start)
      Row() {
        this.edge(true, Alignment.End)
      }.width('100%').height('100%').justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height('100%')
    .opacity(this.breathe)
    .hitTestBehavior(HitTestMode.None)
  }
}
