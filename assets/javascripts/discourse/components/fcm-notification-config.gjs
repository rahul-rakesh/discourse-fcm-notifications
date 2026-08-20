import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { Input } from "@ember/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { extractError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import DConditionalLoadingSpinner from "discourse/ui-kit/d-conditional-loading-spinner";
import { i18n } from "discourse-i18n";
import { subscribe, unsubscribe } from "../lib/fcm-notifications";

const CUSTOM_FIELD = "discourse_fcm_notifications";

export default class FcmNotificationConfig extends Component {
  @service currentUser;
  @service siteSettings;

  @tracked deviceKey = "";
  @tracked loading = false;
  @tracked errorMessage = null;
  @tracked
  subscribed =
    this.currentUser?.custom_fields?.[CUSTOM_FIELD] != null;

  // Enabling needs a key to send; disabling does not.
  get cannotSubscribe() {
    return this.loading || this.deviceKey.length === 0;
  }

  // A rejected request used to go unhandled, leaving the row looking idle after
  // a failure with nothing said. Both paths now surface the reason.
  async #run(request, onSuccess) {
    this.loading = true;
    this.errorMessage = null;

    try {
      const response = await request;

      if (response.success) {
        onSuccess();
        this.subscribed = this.currentUser.custom_fields[CUSTOM_FIELD] != null;
      } else {
        this.errorMessage = response.error;
      }
    } catch (error) {
      this.errorMessage = extractError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  subscribeDevice() {
    const key = this.deviceKey;

    return this.#run(subscribe(key), () => {
      this.currentUser.custom_fields[CUSTOM_FIELD] = key;
    });
  }

  @action
  unsubscribeDevice() {
    return this.#run(unsubscribe(), () => {
      this.currentUser.custom_fields[CUSTOM_FIELD] = null;
    });
  }

  <template>
    {{#if this.siteSettings.fcm_notifications_enabled}}
      <div class="control-group fcm-notifications">
        <label class="control-label">
          {{i18n "discourse_fcm_notifications.title"}}
        </label>

        {{#if this.errorMessage}}
          <div class="alert alert-error">{{this.errorMessage}}</div>
        {{/if}}

        <div class="controls">
          <div>
            {{#if this.subscribed}}
              <DButton
                @icon="far-bell-slash"
                @label="discourse_fcm_notifications.disable"
                @action={{this.unsubscribeDevice}}
                @disabled={{this.loading}}
                class="btn-default"
              />
              <DConditionalLoadingSpinner
                @size="small"
                @condition={{this.loading}}
              />
            {{else}}
              <Input
                @value={{this.deviceKey}}
                placeholder={{i18n
                  "discourse_fcm_notifications.api_key_placeholder"
                }}
                disabled={{this.loading}}
              />
              <DButton
                @icon="far-bell"
                @label="discourse_fcm_notifications.enable"
                @action={{this.subscribeDevice}}
                @disabled={{this.cannotSubscribe}}
                class="btn-default"
              />
              <DConditionalLoadingSpinner
                @size="small"
                @condition={{this.loading}}
              />
              <div class="instructions">
                {{trustHTML (i18n "discourse_fcm_notifications.instructions")}}
              </div>
            {{/if}}
          </div>
        </div>
      </div>
    {{/if}}
  </template>
}
