import { ComposerModel, ComposerScreen } from '../../../main/ets/generated/InteropTextInputHost';
import { ComposerDraftModel } from './ComposerDraftModel';

/** Application-owned model/draft for the second mounted generated instance. */
@ObservedV2
class SecondComposerModel implements ComposerModel {
  commitDraft(_value: string): void {}
  commit(): void {}
}

/** Native parent for the exact CLI-generated composer; no replacement screen. */
@Entry
@ComponentV2
export struct GeneratedComposerHost {
  @Local private draft: string = 'Retained draft';
  @Local private focusRequest: number = 0;
  @Local private secondFocusRequest: number = 0;
  @Local private showComposer: boolean = true;
  @Local private model: ComposerDraftModel = new ComposerDraftModel();
  @Local private secondDraft: string = 'Second retained draft';
  private secondModel: SecondComposerModel = new SecondComposerModel();

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.draft)
          .id('native_parent_draft')
        Text(this.model.lastSubmittedDraft)
          .id('native_submitted_draft')
        Text(`Native commits: ${this.model.commitCount}`)
          .id('native_commit_count')
        Text(`Native draft events: ${this.model.drafts.length}`)
          .id('native_draft_count')
        Text(`Native events: ${this.model.events.join(',')}`)
          .id('native_commit_events')
        Button('Request native focus')
          .id('native_focus_request')
          .onClick((): void => {
            this.focusRequest += 1;
          })
        Button('Focus another control')
          .id('native_other_focus')
          .focusOnTouch(true)
          .onClick((): void => {
            this.getUIContext().getFocusController().requestFocus('native_other_focus');
          })
        Button('Replace committed parent draft')
          .id('native_external_draft')
          .onClick((): void => {
            this.draft = 'External committed edit';
          })
        Button('Remove generated composer')
          .id('native_remove_composer')
          .onClick((): void => {
            this.showComposer = false;
          })
        Button('Restore generated composer')
          .id('native_restore_composer')
          .onClick((): void => {
            this.showComposer = true;
          })
        if (this.showComposer) {
          ComposerScreen({
            draft: this.draft,
            onDraftChange: (value: string): void => {
              this.model.drafts.push(value);
              this.draft = value;
            },
            focusRequest: this.focusRequest,
            onFocusRequestChange: (value: number): void => {
              this.focusRequest = value;
            },
            model: this.model
          })
        }
        Text(this.secondDraft)
          .id('native_second_parent_draft')
        Button('Focus second generated composer')
          .id('native_second_focus_request')
          .onClick((): void => {
            this.secondFocusRequest += 1;
          })
        ComposerScreen({
          draft: this.secondDraft,
          onDraftChange: (value: string): void => {
            this.secondDraft = value;
          },
          focusRequest: this.secondFocusRequest,
          onFocusRequestChange: (value: number): void => {
            this.secondFocusRequest = value;
          },
          model: this.secondModel
        })
      }
      .padding(24)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}
