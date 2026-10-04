import { common } from '@kit.AbilityKit';
import {
  hasSkillErrors, newSkill, SkillErrors, SKILL_BODY_LIMIT, SKILL_DESCRIPTION_LIMIT, SKILL_NAME_LIMIT,
  UserSkill, validateSkill
} from '../agent/Skills';
import { DISPLAY_FONT } from '../common/Fonts';
import { loadSkills, saveSkills } from '../common/Settings';

interface SkillEditParams {
  id?: string;
}

@Entry
@Component
struct SkillEdit {
  @State name: string = '';
  @State description: string = '';
  @State body: string = '';
  @State existing: boolean = false;
  @State saving: boolean = false;
  @State unavailable: boolean = false;
  @State notice: string = '';
  @State errors: SkillErrors = { name: '', description: '', body: '' };
  private skillId: string = '';
  private skillEnabled: boolean = true;
  private saved: UserSkill[] = [];

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    try {
      this.saved = loadSkills(this.ctx(), true);
      const params = this.getUIContext().getRouter().getParams() as SkillEditParams | undefined;
      const id = params?.id ?? '';
      if (id.length === 0) {
        this.skillId = newSkill().id;
        return;
      }
      const skill = this.saved.find((item: UserSkill) => item.id === id);
      if (skill === undefined) {
        this.unavailable = true;
        this.notice = 'This skill is no longer available. Go back to the skill list.';
        return;
      }
      this.skillId = skill.id;
      this.name = skill.name;
      this.description = skill.description;
      this.body = skill.body;
      this.skillEnabled = skill.enabled;
      this.existing = true;
    } catch (error) {
      this.unavailable = true;
      this.notice = `Could not load skill: ${(error as Error).message}`;
    }
  }

  private draft(): UserSkill {
    return {
      id: this.skillId, name: this.name, description: this.description, body: this.body, enabled: this.skillEnabled
    };
  }

  private validate(): void {
    this.errors = validateSkill(this.draft(), this.saved);
  }

  private async save(): Promise<void> {
    if (this.saving || this.unavailable) {
      return;
    }
    this.notice = '';
    try {
      this.saved = loadSkills(this.ctx(), true);
      this.validate();
      if (hasSkillErrors(this.errors)) {
        return;
      }
      const draft = this.draft();
      draft.name = draft.name.trim();
      draft.description = draft.description.trim();
      const others = this.saved.filter((skill: UserSkill) => skill.id !== draft.id);
      others.push(draft);
      this.saving = true;
      await saveSkills(this.ctx(), others);
      this.getUIContext().getRouter().back();
    } catch (error) {
      this.notice = `Could not save skill: ${(error as Error).message}`;
    } finally {
      this.saving = false;
    }
  }

  private confirmDelete(): void {
    AlertDialog.show({
      title: 'Delete skill?',
      message: `Delete "${this.name}"? This removes its saved instructions.`,
      primaryButton: { value: 'Cancel', action: () => {} },
      secondaryButton: { value: 'Delete', fontColor: $r('app.color.danger'), action: () => { this.remove(); } }
    });
  }

  private async remove(): Promise<void> {
    if (this.saving || this.unavailable) {
      return;
    }
    this.saving = true;
    this.notice = '';
    try {
      const skills = loadSkills(this.ctx(), true).filter((skill: UserSkill) => skill.id !== this.skillId);
      await saveSkills(this.ctx(), skills);
      this.getUIContext().getRouter().back();
    } catch (error) {
      this.notice = `Could not delete skill: ${(error as Error).message}`;
    } finally {
      this.saving = false;
    }
  }

  fieldLength(label: string): number {
    return label === 'Name' ? this.name.length : label === 'Description' ? this.description.length : this.body.length;
  }

  fieldErrorText(field: string): string {
    return field === 'name' ? this.errors.name : field === 'description' ? this.errors.description : this.errors.body;
  }

  @Builder
  fieldLabel(label: string, limit: number) {
    Row() {
      Text(label).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).layoutWeight(1)
      Text(`${this.fieldLength(label)}/${limit}`).fontSize(13)
        .fontColor(this.fieldLength(label) > limit ? $r('app.color.danger') : $r('app.color.ink_muted'))
    }.width('100%')
  }

  @Builder
  fieldError(field: string) {
    if (this.fieldErrorText(field).length > 0) {
      Text(this.fieldErrorText(field)).fontSize(13).fontColor($r('app.color.danger')).width('100%')
    }
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Image($r('app.media.ic_back'))
          .id('skill_edit_back').width(24).height(24).fillColor($r('app.color.ink'))
          .padding(10).width(44).height(44).accessibilityText('Back').enabled(!this.saving)
          .onClick(() => this.getUIContext().getRouter().back())
        Text(this.existing ? 'Edit skill' : 'New skill').fontFamily(DISPLAY_FONT).fontSize(24)
          .fontColor($r('app.color.ink')).layoutWeight(1)
        Button('Save').id('save_skill').enabled(!this.saving && !this.unavailable)
          .backgroundColor($r('app.color.orb_violet')).fontColor($r('app.color.on_orb'))
          .margin({ right: 16 }).onClick(() => { this.save(); })
      }.width('100%').height(56)

      Scroll() {
        Column({ space: 18 }) {
          if (this.notice.length > 0) {
            Text(this.notice).fontSize(14).fontColor($r('app.color.danger')).width('100%')
          }
          Column({ space: 10 }) {
            this.fieldLabel('Name', SKILL_NAME_LIMIT)
            TextInput({ placeholder: 'Skill name', text: this.name }).id('skill_name').accessibilityText('Skill name')
              .fontColor($r('app.color.ink')).backgroundColor($r('app.color.bg'))
              .enabled(!this.saving && !this.unavailable).onChange((value: string) => { this.name = value; this.validate(); })
            this.fieldError('name')
            this.fieldLabel('Description', SKILL_DESCRIPTION_LIMIT)
            TextInput({ placeholder: 'When should the agent use this skill?', text: this.description })
              .id('skill_description').accessibilityText('Skill description')
              .fontColor($r('app.color.ink')).backgroundColor($r('app.color.bg'))
              .enabled(!this.saving && !this.unavailable)
              .onChange((value: string) => { this.description = value; this.validate(); })
            this.fieldError('description')
            this.fieldLabel('Body', SKILL_BODY_LIMIT)
            TextArea({ placeholder: 'Instructions for the agent', text: this.body })
              .id('skill_body').accessibilityText('Skill instructions')
              .fontColor($r('app.color.ink')).backgroundColor($r('app.color.bg')).height(240)
              .enabled(!this.saving && !this.unavailable).onChange((value: string) => { this.body = value; this.validate(); })
            this.fieldError('body')
          }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.surface'))

          if (this.existing) {
            Button('Delete skill').id('delete_skill').enabled(!this.saving && !this.unavailable)
              .backgroundColor($r('app.color.surface')).fontColor($r('app.color.danger'))
              .width('100%').onClick(() => this.confirmDelete())
          }
        }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 32 })
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor($r('app.color.bg'))
  }
}
