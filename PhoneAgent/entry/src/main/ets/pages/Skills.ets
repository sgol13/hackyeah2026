import { common } from '@kit.AbilityKit';
import { copySkill, UserSkill } from '../agent/Skills';
import { DISPLAY_FONT } from '../common/Fonts';
import { loadSkills, saveSkills } from '../common/Settings';

@Entry
@Component
struct Skills {
  @State skills: UserSkill[] = [];
  @State saving: boolean = false;
  @State notice: string = '';

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  onPageShow(): void {
    try {
      this.skills = loadSkills(this.ctx(), true);
      this.notice = '';
    } catch (error) {
      this.notice = `Could not load skills: ${(error as Error).message}`;
    }
  }

  private openEditor(id: string = ''): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/SkillEdit', params: { id: id } });
  }

  private async setEnabled(skill: UserSkill, enabled: boolean): Promise<void> {
    if (this.saving || skill.enabled === enabled) {
      return;
    }
    this.saving = true;
    this.notice = '';
    try {
      const updated = loadSkills(this.ctx(), true).map((item: UserSkill) => {
        const copy = copySkill(item);
        if (copy.id === skill.id) {
          copy.enabled = enabled;
        }
        return copy;
      });
      await saveSkills(this.ctx(), updated);
      this.skills = updated;
    } catch (error) {
      this.notice = `Could not save skills: ${(error as Error).message}`;
      this.skills = loadSkills(this.ctx(), true);
    } finally {
      this.saving = false;
    }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 4 }) {
        Image($r('app.media.ic_back'))
          .id('skills_back')
          .width(24).height(24).fillColor($r('app.color.ink'))
          .padding(10).width(44).height(44)
          .accessibilityText('Back').onClick(() => this.getUIContext().getRouter().back())
        Text('Skills').fontFamily(DISPLAY_FONT).fontSize(24).fontColor($r('app.color.ink')).layoutWeight(1)
        Image($r('app.media.ic_add'))
          .id('add_skill')
          .width(24).height(24).fillColor($r('app.color.ink'))
          .padding(10).width(44).height(44)
          .accessibilityText('Add skill').enabled(!this.saving).onClick(() => this.openEditor())
      }.height(56).width('100%')

      if (this.notice.length > 0) {
        Text(this.notice).fontSize(14).fontColor($r('app.color.danger')).width('100%').padding({ left: 16, right: 16 })
      }
      if (this.skills.length === 0) {
        Text('No skills yet. Skills teach the agent how to handle specific apps or tasks. Tap + to add one.')
          .id('skills_empty').fontSize(16).fontColor($r('app.color.ink_muted'))
          .width('100%').padding(24)
        Blank()
      } else {
        List({ space: 12 }) {
          ForEach(this.skills, (skill: UserSkill) => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 6 }) {
                  Text(skill.name).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  Text(skill.description).fontSize(14).fontColor($r('app.color.ink_muted'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                .id(`skill_${skill.id}`).accessibilityText(`Edit skill ${skill.name}`)
                .enabled(!this.saving).onClick(() => this.openEditor(skill.id))
                Toggle({ type: ToggleType.Switch, isOn: skill.enabled })
                  .id(`skill_enabled_${skill.id}`).accessibilityText(`Enable skill ${skill.name}`)
                  .selectedColor($r('app.color.orb_violet')).enabled(!this.saving)
                  .onChange((on: boolean) => { this.setEnabled(skill, on); })
              }.padding(16).width('100%').borderRadius(20).backgroundColor($r('app.color.surface'))
            }
          }, (skill: UserSkill) => `${skill.id}:${skill.name}:${skill.description}:${skill.enabled}`)
        }.layoutWeight(1).width('100%').padding({ left: 16, right: 16, bottom: 24 })
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.bg'))
  }
}
