/** Task input with the round gradient Run/Stop button. Used by the main screen and the overlay sheet. */
@Component
export struct Composer {
  @Link text: string;
  @Prop running: boolean = false;
  /** false while the service is off or a start is in progress */
  @Prop canRun: boolean = true;
  placeholder: string = 'Ask Oniro Agent to do something';
  onRun: () => void = () => {
  };
  onStop: () => void = () => {
  };

  private active(): boolean {
    return this.running || (this.canRun && this.text.trim().length > 0);
  }

  build() {
    Row({ space: 8 }) {
      TextArea({ placeholder: this.placeholder, text: this.text })
        .id('task')
        .layoutWeight(1)
        .fontSize(17)
        .fontColor($r('app.color.ink'))
        .placeholderColor($r('app.color.ink_muted'))
        .backgroundColor(Color.Transparent)
        .constraintSize({ minHeight: 48, maxHeight: 140 })
        .enabled(!this.running)
        .onChange((v: string) => {
          this.text = v;
        })
      Column() {
        Image(this.running ? $r('app.media.ic_stop') : $r('app.media.ic_arrow_up'))
          .width(22)
          .height(22)
          .fillColor($r('app.color.on_orb'))
      }
      .id('run')
      .width(48)
      .height(48)
      .borderRadius(24)
      .justifyContent(FlexAlign.Center)
      .linearGradient({
        angle: 135,
        colors: [[$r('app.color.orb_teal'), 0], [$r('app.color.orb_violet'), 0.55], [$r('app.color.orb_coral'), 1]]
      })
      .opacity(this.active() ? 1 : 0.35)
      .accessibilityText(this.running ? 'Stop' : 'Run')
      .onClick(() => {
        if (this.running) {
          this.onStop();
        } else if (this.active()) {
          this.onRun();
        }
      })
    }
    .alignItems(VerticalAlign.Bottom)
    .padding({ left: 16, right: 6, top: 6, bottom: 6 })
    .borderRadius(28)
    .backgroundColor($r('app.color.surface_raised'))
    .border({ width: 1, color: $r('app.color.line') })
  }
}
