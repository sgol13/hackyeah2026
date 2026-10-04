/** The OA mark: gradient ring ("O") + arrowhead spark ("A"). The ring turns while the agent works. */
@Component
export struct OaMark {
  // not `size`: that name is taken by the built-in size attribute of every component
  @Prop markSize: number = 40;
  @Prop @Watch('onSpinning') spinning: boolean = false;
  @State private angle: number = 0;

  aboutToAppear(): void {
    this.onSpinning();
  }

  onSpinning(): void {
    if (this.spinning) {
      this.getUIContext().animateTo({ duration: 1400, curve: Curve.Linear, iterations: -1 }, () => {
        this.angle = 360;
      });
    } else {
      this.getUIContext().animateTo({ duration: 0 }, () => {
        this.angle = 0;
      });
    }
  }

  build() {
    Stack() {
      Image($r('app.media.oa_ring'))
        .width(this.markSize)
        .height(this.markSize)
        .rotate({ angle: this.angle, centerX: '45%', centerY: '55%' })
      Image($r('app.media.oa_spark'))
        .width(this.markSize)
        .height(this.markSize)
    }
    .width(this.markSize)
    .height(this.markSize)
    .accessibilityText('Oniro Agent')
  }
}
