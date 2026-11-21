import { ComposerScreen } from '../../../main/ets/generated/InteropTextInputHost';
import { ComposerDraftModel } from './ComposerDraftModel';

/** Native parent for the exact CLI-generated composer; no replacement screen. */
@Entry
@ComponentV2
export struct GeneratedComposerHost {
  @Local private draft: string = 'Retained draft';
  @Local private focusRequest: number = 0;
  @Local private showComposer: boolean = true;
  @Local private model: ComposerDraftModel = new ComposerDraftModel();

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
          .onClick((): void => {})
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
      }
      .padding(24)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}
