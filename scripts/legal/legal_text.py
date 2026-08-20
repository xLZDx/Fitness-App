# -*- coding: utf-8 -*-
"""Canonical Terms of Service and Privacy Policy, EN + RU.

## Why the text lives here and not in the .arb or the .html

It has to appear in three places: the in-app pages (`privacy_page.dart`,
`terms_page.dart`, via the generated l10n), and two public URLs on Firebase
Hosting that Google Play requires as a store-listing field. Three hand-written
copies of a legal document drift, and legal text that drifts is worse than
useless -- the version a user agreed to stops being knowable.

Same reasoning the repo already applies to `Injury.toJson`, `UserProfile
.toJson` and `kFunctionsRegion`: one source, generated outward. `build_legal.py`
is the generator.

## Every factual claim here was verified against the code

Nothing in this text is aspirational or boilerplate. The claims map to:

  - health fields collected .......... profile_models.dart:203-266
  - health answers stay on device .... sensitive_profile.dart (what counts),
                                       device_health_profile_repository.dart
                                       (the split), main.dart binds it;
                                       H1b cleared the 14 documents already
                                       written, verified by a read-only query
                                       returning 0 still carrying the block
  - passphrase backup exists ......... backup_envelope.dart, backup_page.dart,
                                       route /backup off settings_page.dart
  - Android backup is the user's ..... no allowBackup/dataExtractionRules in
                                       AndroidManifest.xml, so the platform
                                       default applies; encrypted since
                                       Android 9 with a lock-screen-derived key
  - anonymous / Google sign-in ....... firebase_auth_repository.dart:64, :104
  - health data never sent to AI ..... ai_coach_service.dart:33-40 (machine
                                       name + language are the whole prompt)
  - gym photo IS sent to Gemini ...... gemini_equipment_service.dart:37-48,
                                       and app_en.arb:877 already says so
  - progress photos stay local ....... progress_photos_providers.dart:13 is a
                                       Mock; index.ts:1163 confirms there is
                                       nothing in Cloud Storage to delete
  - no ad id / no analytics SDK ...... pubspec.yaml has crashlytics + firebase_ai
                                       and no admob / analytics / attribution.
                                       The old wording also promised "there is
                                       no advertising", which was dropped
                                       deliberately: the operator intends a
                                       promotions section carrying offers from
                                       gyms, trainers and shops, and a promise
                                       due to break is worse than one never
                                       made. What remains is narrower and
                                       stays true -- first-party promotions
                                       need no advertising identifier and no
                                       third-party SDK.
                                       Health data must never target them:
                                       Play forbids it and GDPR Art. 9 covers
                                       it, which the device-only split above
                                       now enforces structurally.
  - EU storage ....................... Firestore eur3, functions europe-west1
  - supporter wall limits ............ index.ts:741-756 (60 / 200 chars)
  - deletion is irreversible ......... index.ts:1169-1207
  - export / delete UI paths ......... settings_page.dart:195, :272
  - prices ........................... subscription_page.dart:960-977
  - 15% coach fee .................... index.ts:985

## Markup

A deliberately tiny subset, rendered by two consumers (`_LegalBody` in Dart,
`_html_of` in build_legal.py):

  `## `  at the start of a block -> heading
  `- `   at the start of a line  -> bullet
  `**x**` inline                 -> bold
  blank line                     -> paragraph break

Anything richer would need a Markdown dependency on both sides to render two
static documents, which is not a trade worth making.
"""

#: The whole sentence per language, not a date plus a translated label. A
#: `"Last updated {date}"` placeholder would need `@`-metadata in both .arb
#: files and would still render an ISO date to a reader — one key each says
#: the same thing in the form each language actually writes it.
STAMP = {
    "en": "Last updated 21 August 2026",
    "ru": "Обновлено 21 августа 2026",
}

# --------------------------------------------------------------------------
# Privacy Policy
# --------------------------------------------------------------------------

PRIVACY_EN = """\
## Who is responsible

Fitness App is built and run by one independent developer, based in Chisinau, \
Moldova. There is no company and no nonprofit behind it. Questions about this \
policy or about your data: korostelevivan@gmail.com.

## The short version

- Your health answers are used to filter exercises away from your injuries. \
They are never sold, and they are never sent to an AI model.
- Photos you take of gym machines are sent to Google's Gemini to be \
recognised. Other people may be in shot.
- What we hold is stored in Google Cloud data centres in the European Union. \
The one thing that leaves our systems by design is an equipment report you \
send to a gym with its own maintenance channel -- see "Equipment reports" \
below.
- You can export everything we hold, and delete it permanently, from inside \
the app. A report already forwarded to a gym is outside our systems by then, \
so deleting your account does not recall it.

## What is collected

**Your account.** You can sign in anonymously or with Google. An anonymous \
account carries no name and no email address. If you sign in with Google, the \
app receives the name, email address and profile picture on that Google \
account.

**Health and fitness answers.** The onboarding questionnaire asks for age, \
gender, height, current and target weight, and activity level; medical \
conditions, allergies, medications, injuries, physical limitations, recent \
surgeries, blood pressure, and anything else you choose to type in; smoking, \
alcohol, sleep, stress, diet, and how active your work is; and your goals, \
training experience and equipment access.

Under the GDPR and most comparable laws, much of that is health data -- a \
special category with extra protection. It is asked for one purpose: to keep \
movements that conflict with an injury or condition out of your plan, and to \
size that plan to you. Every field can be left blank, and the app still works.

**The health answers stay on your phone.** The medical part of that \
questionnaire -- conditions, allergies, medications, injuries, physical \
limitations, recent surgeries, blood pressure, your own notes, and your \
smoking and alcohol answers -- is stored on your device and is not sent to \
this app's servers. Nothing on the server ever read it, so there was no reason \
to hold it there.

One exception, and it is historical rather than current. Accounts that answered \
the questionnaire before 6 August 2026 had those answers held on the server, \
because that is where the app kept them at the time. Opening the app moves them \
down to your device and deletes the server copy, and deleting your account \
removes them either way -- but an account nobody has opened since may still \
have a copy sitting there. If that could be yours, opening the app once is \
enough.

Two things follow from that, and both are yours to weigh. If you reinstall the \
app or move to another phone, those answers do not come back on their own; \
Settings has a passphrase-protected backup that carries them, and a forgotten \
passphrase cannot be recovered by anyone, us included. And if you have \
Android's own backup switched on, your device's data -- this included -- is \
copied to your personal Google account and encrypted with a key derived from \
your screen lock. That copy is yours, not ours, and we cannot read it.

**What you do in the app.** Completed workouts with sets and weights, \
statistics, scheduled sessions, machines you have scanned, notes on those \
machines, and exercises the AI generated for you.

**Payments.** Card details go to Stripe and never reach this app's servers. \
What is stored here is your subscription tier and status, plus the Stripe \
customer and subscription identifiers needed to manage it.

**Camera and photos.** To identify a gym machine, the photo is resized and \
sent to Google's Gemini model. If that call fails, a smaller model running on \
your phone is used instead. The photo itself is not kept afterwards -- what is \
kept is which machine was identified. A gym is a shared space, so be aware \
that other people may be in the frame.

Progress photos are different: they stay on your phone. There is no \
server-side storage for them at all.

**Equipment reports.** If you report broken or missing equipment and name the \
gym you are at, that report -- including anything you typed in the note -- \
goes to this app's own records, and separately to that gym's own maintenance \
channel, if the gym has registered one. Which system that is depends on \
which gym you name; it is not one of the two processors below, and this app \
does not control what that gym does with it afterwards. If the gym you name \
has not registered a channel, or you leave the field blank, the report only \
ever reaches this app's own records.

**Health Connect and Apple Health.** If you connect them, the app reads five \
things: steps, active calories burned, resting heart rate, sleep, and heart \
rate variability. It writes one thing back: a workout entry when you finish a \
session, so your other apps know you trained.

Those readings never leave your phone. They are held in memory while the app \
is open, shown to you on the home screen, and used to judge whether to suggest \
an easier week. They are not written to this app's servers, not included in \
your account, and not sent to any AI model. Nothing is read until you grant \
the permission, and revoking it in Health Connect or Apple Health stops the \
reading immediately -- the app keeps working without it.

**Crash reports.** When the app crashes, Firebase Crashlytics receives the \
device model, the OS version and the stack trace. It is switched off in \
development builds.

## What is not done

- Your data is not sold, and never has been.
- Health answers are never sent to any AI model. The in-app coach receives \
only the name of the machine you asked about and your language -- nothing else.
- No advertising identifier is collected, and no third-party analytics or \
attribution SDK is built into the app.

## Where it is stored, and who else touches it

Data lives in Google Cloud's eur3 multi-region, inside the European Union, and \
the server code that reads it runs in europe-west1. Firestore security rules \
restrict every document under your account to you alone.

Two processors handle everything else: Google (Firebase Authentication, \
Firestore, Crashlytics, App Check, and the Gemini model) and Stripe \
(payments). A gym you name in an equipment report can be a third recipient of \
that report's contents, but only that report, and only when that specific \
gym has registered its own maintenance channel -- see "Equipment reports" \
above. Unlike Google and Stripe, a gym does not act on this app's \
instructions and nothing here governs what it does with what it receives.

## The supporter wall is public, and only by your own request

If you opt in, a display name you choose (up to 60 characters) and an optional \
message (up to 200 characters) become readable by anyone. Leave the name blank \
and the entry shows as anonymous. Opting out removes it. Nothing else about \
you is ever published.

## How long it is kept

Your data is kept while your account exists, and goes when you delete it. \
There is no separate retention timer and no archive copy kept afterwards.

Two kinds of record are shared with someone else, and those are kept with your \
identifier removed rather than deleted: a coach booking, which is also the \
coach's record of a session that really happened, and an equipment report, \
which is a fault the gym still has to fix. Nothing left in them identifies \
you, and a booking whose other side has also deleted their account is removed \
outright. Anything you wrote in the text of a report stays as written, so do \
not put anything personal in one.

Stripe keeps its own payment records for as long as its own legal obligations \
require. Those are outside this app's control and cannot be deleted from here.

## Your rights

**Export** -- Settings, then "Export your data". You get your profile, your \
health answers, your whole workout history, your schedule and the details of \
every progress photo, in a machine-readable file. The one thing it does not \
carry is the progress-photo images themselves: they are encrypted with a key \
that does not leave your device, so the export lists each photo and says so \
in the file rather than shipping bytes nothing could open.

**Deletion** -- Settings, then "Delete account". This cancels any active \
subscription, erases every document under your account, and then deletes the \
account itself. It is irreversible: afterwards there is nothing left to \
restore, including for us.

If you are in the EU, the UK, or anywhere with comparable law, you can also \
object to processing, ask for a correction, and complain to your data \
protection authority. Write to the address above and it will be acted on.

## Children

An account of your own requires you to be at least 16, and data is not \
knowingly collected from anyone younger. If you believe a younger child has an \
account here, write and it will be deleted.

The exercises themselves carry no age restriction. A parent or guardian \
training a younger child from their own account is the intended way to do \
that -- the limit is on the account, which holds health answers and a payment \
method, not on who may exercise.

## Changes to this policy

The date at the top is the version. There is no in-app notification when this \
text changes -- if that matters to you, this page is where to check.
"""

PRIVACY_RU = """\
## Кто отвечает за приложение

Fitness App делает и поддерживает один независимый разработчик, Кишинёв, \
Молдова. За приложением нет ни компании, ни некоммерческой организации. \
Вопросы по этой политике и по вашим данным: korostelevivan@gmail.com.

## Коротко

- Ответы о здоровье нужны, чтобы убирать из плана упражнения, которые \
конфликтуют с вашими травмами. Их не продают и не отправляют в ИИ-модель.
- Фотографии тренажёров, которые вы делаете, отправляются в Google Gemini для \
распознавания. В кадр могут попасть посторонние люди.
- То, что храним мы, лежит в дата-центрах Google Cloud на территории \
Европейского союза. Единственное, что по замыслу покидает наши системы -- \
сообщение о неисправном оборудовании, если вы отправили его в зал с \
собственным каналом техобслуживания -- см. «Сообщения о неисправном \
оборудовании» ниже.
- Всё, что храним мы, можно выгрузить и можно безвозвратно удалить прямо из \
приложения. Сообщение, уже переданное залу, к этому моменту вне наших систем, \
поэтому удаление аккаунта его не отзывает.

## Какие данные собираются

**Учётная запись.** Войти можно анонимно или через Google. У анонимной \
учётной записи нет ни имени, ни адреса почты. При входе через Google \
приложение получает имя, адрес почты и фотографию профиля этой учётной \
записи Google.

**Ответы о здоровье и физической форме.** Анкета при первом запуске \
спрашивает возраст, пол, рост, текущий и целевой вес, уровень активности; \
заболевания, аллергии, лекарства, травмы, физические ограничения, недавние \
операции, давление и всё, что вы допишете сами; курение, алкоголь, сон, \
уровень стресса, питание и насколько подвижная у вас работа; а также цели, \
опыт тренировок и доступное оборудование.

По GDPR и большинству сопоставимых законов значительная часть этого -- данные \
о здоровье, особая категория с усиленной защитой. Они запрашиваются ради \
одного: убирать из вашего плана движения, которые конфликтуют с травмой или \
заболеванием, и подбирать нагрузку под вас. Любое поле можно оставить пустым, \
приложение продолжит работать.

**Ответы о здоровье остаются на вашем телефоне.** Медицинская часть анкеты -- \
заболевания, аллергии, лекарства, травмы, физические ограничения, недавние \
операции, давление, ваши собственные заметки, а также ответы про курение и \
алкоголь -- хранится на устройстве и не отправляется на серверы этого \
приложения. На сервере это никто и никогда не читал, поэтому держать их там \
было незачем.

Одно исключение, и оно историческое, а не текущее. У учётных записей, \
заполнивших анкету до 6 августа 2026 года, эти ответы хранились на сервере -- \
тогда приложение держало их именно там. При открытии приложения они \
переносятся на устройство, а серверная копия удаляется; удаление учётной \
записи убирает их в любом случае. Но у записи, которую с тех пор никто не \
открывал, копия может ещё лежать там. Если это может быть ваш случай, \
достаточно один раз открыть приложение.

Отсюда два следствия, и оба вам стоит взвесить. При переустановке приложения \
или переходе на другой телефон эти ответы сами не вернутся; в настройках есть \
резервная копия под парольной фразой, которая их переносит, и забытую фразу не \
восстановит никто, включая нас. А если у вас включена собственная резервная \
копия Android, данные устройства -- в том числе эти -- копируются в ваш личный \
аккаунт Google и шифруются ключом, производным от кода блокировки экрана. Эта \
копия ваша, а не наша, и прочитать её мы не можем.

**Что вы делаете в приложении.** Завершённые тренировки с подходами и весами, \
статистика, запланированные занятия, отсканированные тренажёры, заметки по \
ним и упражнения, сгенерированные ИИ.

**Платежи.** Данные карты уходят в Stripe и никогда не попадают на серверы \
этого приложения. Здесь хранятся уровень и статус подписки, а также \
идентификаторы клиента и подписки Stripe, нужные для управления ею.

**Камера и фотографии.** Чтобы определить тренажёр, фотография уменьшается и \
отправляется в модель Google Gemini. Если этот вызов не удался, используется \
меньшая модель на самом телефоне. Сама фотография потом не хранится -- \
сохраняется только то, какой тренажёр был определён. Зал -- общее \
пространство, помните, что в кадр могут попасть посторонние.

С фотографиями прогресса иначе: они остаются на телефоне. Серверного \
хранилища для них нет вообще.

**Сообщения о неисправном оборудовании.** Если вы сообщаете о сломанном или \
отсутствующем оборудовании и указываете зал, это сообщение -- включая всё, \
что вы написали в примечании, -- попадает в собственные записи этого \
приложения, а отдельно -- в канал техобслуживания этого зала, если у него \
такой зарегистрирован. Какая это система, зависит от того, какой зал вы \
указали; это не один из двух обработчиков ниже, и это приложение не \
контролирует, что этот зал делает с сообщением дальше. Если у указанного \
зала канал не зарегистрирован или поле оставлено пустым, сообщение доходит \
только до собственных записей этого приложения.

**Health Connect и Apple Health.** Если вы их подключите, приложение читает \
пять показателей: шаги, активные калории, пульс покоя, сон и вариабельность \
сердечного ритма. Записывает обратно одно: запись о тренировке по завершении \
занятия, чтобы другие ваши приложения знали, что вы тренировались.

Эти показания не покидают телефон. Они держатся в памяти, пока приложение \
открыто, показываются вам на главном экране и используются, чтобы решить, не \
предложить ли неделю полегче. Они не пишутся на серверы этого приложения, не \
входят в вашу учётную запись и не отправляются ни в одну модель ИИ. Ничего не \
читается, пока вы не дали разрешение, а отзыв доступа в Health Connect или \
Apple Health немедленно прекращает чтение -- приложение продолжает работать и \
без него.

**Отчёты о сбоях.** При падении приложения Firebase Crashlytics получает \
модель устройства, версию ОС и трассировку стека. В отладочных сборках это \
отключено.

## Чего не происходит

- Ваши данные не продаются и никогда не продавались.
- Ответы о здоровье не отправляются ни в какую ИИ-модель. Встроенный \
советчик получает только название тренажёра, о котором вы спросили, и язык -- \
больше ничего.
- Рекламный идентификатор не собирается, и в приложении не встроено ни одного \
стороннего SDK аналитики или атрибуции.

## Где данные хранятся и кто ещё их касается

Данные лежат в мультирегионе Google Cloud eur3, на территории Европейского \
союза, а серверный код, который их читает, работает в europe-west1. Правила \
безопасности Firestore ограничивают доступ к каждому документу вашей учётной \
записи только вами.

Всё остальное обрабатывают два обработчика: Google (Firebase Authentication, \
Firestore, Crashlytics, App Check и модель Gemini) и Stripe (платежи). \
Указанный вами в сообщении об оборудовании зал может стать третьим \
получателем содержимого этого сообщения -- но только этого сообщения, и \
только если у этого конкретного зала зарегистрирован собственный канал \
техобслуживания -- см. «Сообщения о неисправном оборудовании» выше. В \
отличие от Google и Stripe, зал не действует по инструкциям этого \
приложения, и оно никак не контролирует, что зал делает с полученным.

## Стена поддержки публична -- и только по вашей просьбе

Если вы согласились её показывать, выбранное вами отображаемое имя (до 60 \
символов) и необязательное сообщение (до 200 символов) становятся доступны \
всем. Оставьте имя пустым -- запись будет анонимной. Отказ убирает её. Ничего \
другого о вас не публикуется никогда.

## Сколько данные хранятся

Данные хранятся, пока существует ваша учётная запись, и исчезают, когда вы её \
удаляете. Отдельного таймера хранения нет, архивной копии после удаления не \
остаётся.

Две записи принадлежат не только вам, и они не удаляются, а сохраняются без \
вашего идентификатора: запись о занятии с тренером -- это одновременно и его \
запись о состоявшемся занятии -- и сообщение о неисправном оборудовании, \
которое залу ещё предстоит починить. В том, что остаётся, вас ничто не \
называет, а запись о занятии, вторая сторона которого тоже удалила учётную \
запись, удаляется целиком. Текст сообщения об оборудовании остаётся таким, как \
вы его написали, поэтому не пишите в нём ничего личного.

Stripe хранит собственные платёжные записи столько, сколько требуют его \
собственные обязательства. Это вне контроля приложения и отсюда не удаляется.

## Ваши права

**Выгрузка** -- «Настройки», затем «Выгрузить мои данные». В машиночитаемом \
файле вы получаете профиль, ответы о здоровье, всю историю тренировок, \
расписание и сведения о каждой фотографии прогресса. Единственное, чего в \
файле нет, -- сами изображения: они зашифрованы ключом, который не покидает \
ваше устройство, поэтому выгрузка перечисляет каждую фотографию и прямо \
сообщает об этом, а не кладёт внутрь байты, которые всё равно никто не \
откроет.

**Удаление** -- «Настройки», затем «Удалить аккаунт». Это отменяет активную \
подписку, стирает все документы вашей учётной записи, а затем удаляет саму \
запись. Действие необратимо: после него восстанавливать нечего, в том числе и \
нам.

Если вы в ЕС, Великобритании или там, где действует сопоставимый закон, вы \
также вправе возразить против обработки, потребовать исправления и подать \
жалобу в свой надзорный орган по защите данных. Напишите по адресу выше -- \
обращение будет отработано.

## Дети

Собственный аккаунт можно завести с 16 лет; данные тех, кто младше, осознанно \
не собираются. Если вы считаете, что учётную запись здесь завёл ребёнок \
младше, напишите -- она будет удалена.

Сами упражнения возрастных ограничений не имеют. Родитель или опекун, \
тренирующий ребёнка младше со своего аккаунта, -- это предусмотренный \
сценарий: ограничение стоит на аккаунте, в котором лежат ответы о здоровье и \
привязана оплата, а не на том, кому можно заниматься.

## Изменения этой политики

Дата вверху -- это версия. Уведомления в приложении об изменении этого текста \
нет; если это важно, проверять нужно на этой странице.
"""

# --------------------------------------------------------------------------
# Terms of Service
# --------------------------------------------------------------------------

TERMS_EN = """\
## Who you are agreeing with

Fitness App is built and run by one independent developer, based in Chisinau, \
Moldova. There is no company and no nonprofit behind it. Contact: \
korostelevivan@gmail.com.

Creating an account, or continuing to use the app, means you accept these \
terms.

## What this app is, and what it is not

It is an exercise catalogue, a workout planner and a machine scanner. It is \
not a medical service, and nothing in it is medical advice, diagnosis or \
treatment.

Exercise carries a real risk of injury. The app screens exercises against the \
injuries you enter, but that screening is a filter over tags in a catalogue -- \
it is not an examination and it cannot know your body. **The exercise library \
has not been reviewed by a physiotherapist.** If you have an injury or a \
medical condition, or you are unsure, ask a qualified professional before you \
train, and stop if something hurts.

You train at your own risk. That is not a formality -- it is the actual \
arrangement.

## Age

You need to be at least 16 to have an account of your own.

That is a limit on the account, not on the exercises. The account holds health \
answers and a payment method, which is what the age rule is about; nothing in \
the catalogue is age-restricted, and a parent or guardian is free to train a \
younger child using their own account.

## Your account

You can use the app anonymously or sign in with Google. You are responsible \
for what happens under your account. An anonymous account is tied to that one \
installation -- sign in with Google if you want it to survive a lost phone.

## Subscriptions and payment

There is a free tier. The paid tiers are:

- Supporter -- $9.99 per month, or $59.99 per year
- Supporter, 2 seats -- $14.99 per month
- Supporter, 4 seats -- $19.99 per month
- Sustainer -- $19.99 per month, or $119.99 per year
- Sustainer, lifetime -- $499 once

A 14-day free trial is available once per account.

Payment is handled by Stripe. Subscriptions renew automatically until \
cancelled. You can cancel at any time from the billing portal inside the app, \
and access continues to the end of the period you have already paid for. \
Prices are in US dollars and can change -- a change never applies to a period \
already paid for.

**These payments are not tax-deductible donations.** There is no nonprofit \
status and no fiscal sponsor behind this app. "Supporter" and "Sustainer" are \
the names of subscription tiers, nothing more.

Refunds are not automatic. If something went wrong, write, and it will be \
dealt with case by case.

## Coaches

Where coach booking is available, coaches are independent people rather than \
employees, and are responsible for their own services and their own \
qualifications. A platform fee of 15% is taken from each booking. This app is \
not a party to what happens in a session between you and a coach.

## What you contribute

Equipment reports, machine notes and your supporter-wall message stay yours. \
By submitting them, you allow them to be stored and shown for the purpose they \
exist for -- an equipment report to be kept in this app's own records and, \
when the gym you name has registered a maintenance channel, forwarded there \
too (see the Privacy Policy's "Equipment reports" section), a wall message to \
appear on the public wall. Do not submit anything unlawful, or anything you \
have no right to submit.

## Ending it

You can delete your account at any time from Settings. That cancels any \
subscription and erases your data irreversibly. Access may be withdrawn from \
anyone who abuses the service or breaks these terms.

## Limits

The app is provided as it is. It is a single-developer project: it can have \
bugs, it can be unavailable, and a recommendation it produces can be wrong for \
you. To the extent the law allows, no liability is accepted for injury, loss \
or damage arising from use of the app. Nothing here limits liability that \
cannot lawfully be limited.

## Law and disputes

These terms are governed by the law of the Republic of Moldova. If you are a \
consumer elsewhere, the mandatory consumer protections of your own country \
still apply to you regardless. Write first -- most things are solvable that \
way.

## Changes

The date at the top is the version. There is no in-app notification when these \
terms change; continuing to use the app after a change means accepting it.
"""

TERMS_RU = """\
## С кем вы заключаете соглашение

Fitness App делает и поддерживает один независимый разработчик, Кишинёв, \
Молдова. За приложением нет ни компании, ни некоммерческой организации. \
Связь: korostelevivan@gmail.com.

Создание учётной записи или продолжение пользования приложением означает \
согласие с этими условиями.

## Что это приложение такое и чем оно не является

Это каталог упражнений, планировщик тренировок и сканер тренажёров. Это не \
медицинская услуга, и ничто здесь не является медицинской консультацией, \
диагнозом или лечением.

Тренировки несут реальный риск травмы. Приложение отсеивает упражнения по \
травмам, которые вы указали, но этот отсев -- фильтр по меткам в каталоге, а \
не осмотр, и о вашем теле он ничего не знает. **Каталог упражнений не \
проверялся физиотерапевтом.** Если у вас травма или заболевание, либо вы не \
уверены, спросите квалифицированного специалиста до тренировки и \
остановитесь, если появилась боль.

Вы тренируетесь на свой риск. Это не формальность, а фактическое положение \
дел.

## Возраст

Собственный аккаунт можно завести с 16 лет.

Это ограничение на аккаунт, а не на упражнения. В аккаунте лежат ответы о \
здоровье и привязана оплата -- именно поэтому есть возрастное правило; в \
каталоге нет ничего с возрастным ограничением, и родитель или опекун вправе \
тренировать ребёнка младше со своего аккаунта.

## Ваша учётная запись

Приложением можно пользоваться анонимно или войти через Google. Вы отвечаете \
за то, что происходит под вашей учётной записью. Анонимная запись привязана к \
одной установке -- войдите через Google, если хотите, чтобы она пережила \
потерю телефона.

## Подписки и оплата

Есть бесплатный уровень. Платные:

- Supporter -- $9.99 в месяц или $59.99 в год
- Supporter, 2 места -- $14.99 в месяц
- Supporter, 4 места -- $19.99 в месяц
- Sustainer -- $19.99 в месяц или $119.99 в год
- Sustainer, пожизненно -- $499 единоразово

Бесплатный пробный период на 14 дней доступен один раз на учётную запись.

Оплату обрабатывает Stripe. Подписка продлевается автоматически, пока её не \
отменят. Отменить можно в любой момент через платёжный портал в приложении, \
доступ сохраняется до конца уже оплаченного периода. Цены указаны в долларах \
США и могут меняться -- изменение никогда не распространяется на уже \
оплаченный период.

**Эти платежи не являются пожертвованиями, вычитаемыми из налога.** У \
приложения нет ни некоммерческого статуса, ни фискального спонсора. \
«Supporter» и «Sustainer» -- это названия уровней подписки, не более того.

Возвраты не автоматические. Если что-то пошло не так -- напишите, разберём \
каждый случай отдельно.

## Тренеры

Там, где доступна запись к тренеру, тренеры -- независимые люди, а не \
сотрудники, и сами отвечают за свои услуги и свою квалификацию. С каждой \
записи удерживается комиссия платформы 15%. Приложение не является стороной \
того, что происходит на занятии между вами и тренером.

## Что вы добавляете сами

Сообщения о тренажёрах, заметки по ним и ваше сообщение на стене поддержки \
остаются вашими. Отправляя их, вы разрешаете хранить и показывать их ради \
того, для чего они существуют: сообщение о тренажёре -- чтобы попасть в \
собственные записи этого приложения и, если указанный вами зал зарегистрировал \
канал техобслуживания, быть также переданным туда (см. раздел «Сообщения о \
неисправном оборудовании» в Политике конфиденциальности), сообщение на стене \
-- чтобы появиться на публичной стене. Не отправляйте противоправное и то, на \
что у вас нет прав.

## Прекращение

Удалить учётную запись можно в любой момент в «Настройках». Это отменяет \
подписку и необратимо стирает ваши данные. Доступ может быть закрыт тем, кто \
злоупотребляет сервисом или нарушает эти условия.

## Ограничения

Приложение предоставляется как есть. Это проект одного разработчика: в нём \
могут быть ошибки, он может быть недоступен, а выданная им рекомендация может \
вам не подойти. В пределах, допускаемых законом, ответственность за травмы, \
убытки или ущерб от использования приложения не принимается. Ничто здесь не \
ограничивает ответственность, которую нельзя ограничить по закону.

## Право и споры

Эти условия регулируются правом Республики Молдова. Если вы потребитель в \
другой стране, обязательные нормы защиты прав потребителей вашей страны всё \
равно применяются к вам. Сначала напишите -- так решается почти всё.

## Изменения

Дата вверху -- это версия. Уведомления в приложении об изменении условий нет; \
продолжение пользования после изменения означает согласие с ним.
"""

DOCS = {
    "privacy": {"en": PRIVACY_EN, "ru": PRIVACY_RU},
    "terms": {"en": TERMS_EN, "ru": TERMS_RU},
}

TITLES = {
    "privacy": {"en": "Privacy Policy", "ru": "Политика конфиденциальности"},
    "terms": {"en": "Terms of Service", "ru": "Условия использования"},
}
