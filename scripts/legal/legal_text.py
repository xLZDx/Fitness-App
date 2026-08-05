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
  - anonymous / Google sign-in ....... firebase_auth_repository.dart:64, :104
  - health data never sent to AI ..... ai_coach_service.dart:33-40 (machine
                                       name + language are the whole prompt)
  - gym photo IS sent to Gemini ...... gemini_equipment_service.dart:37-48,
                                       and app_en.arb:877 already says so
  - progress photos stay local ....... progress_photos_providers.dart:13 is a
                                       Mock; index.ts:1163 confirms there is
                                       nothing in Cloud Storage to delete
  - no ads / no analytics SDK ........ pubspec.yaml has crashlytics + firebase_ai
                                       and no admob / analytics / attribution
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

LAST_UPDATED = "2026-08-05"

#: The whole sentence per language, not a date plus a translated label. A
#: `"Last updated {date}"` placeholder would need `@`-metadata in both .arb
#: files and would still render an ISO date to a reader — one key each says
#: the same thing in the form each language actually writes it.
STAMP = {
    "en": "Last updated 5 August 2026",
    "ru": "Обновлено 5 августа 2026",
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
- Everything is stored in Google Cloud data centres in the European Union.
- You can export all of it, and you can delete all of it permanently, from \
inside the app.

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

**Crash reports.** When the app crashes, Firebase Crashlytics receives the \
device model, the OS version and the stack trace. It is switched off in \
development builds.

## What is not done

- Your data is not sold, and never has been.
- Health answers are never sent to any AI model. The in-app coach receives \
only the name of the machine you asked about and your language -- nothing else.
- There is no advertising, no advertising identifier is collected, and no \
third-party analytics or attribution SDK is built into the app.

## Where it is stored, and who else touches it

Data lives in Google Cloud's eur3 multi-region, inside the European Union, and \
the server code that reads it runs in europe-west1. Firestore security rules \
restrict every document under your account to you alone.

Two processors are involved, and no others: Google (Firebase Authentication, \
Firestore, Crashlytics, App Check, and the Gemini model) and Stripe \
(payments).

## The supporter wall is public, and only by your own request

If you opt in, a display name you choose (up to 60 characters) and an optional \
message (up to 200 characters) become readable by anyone. Leave the name blank \
and the entry shows as anonymous. Opting out removes it. Nothing else about \
you is ever published.

## How long it is kept

Your data is kept while your account exists, and goes when you delete it. \
There is no separate retention timer and no archive copy kept afterwards.

Stripe keeps its own payment records for as long as its own legal obligations \
require. Those are outside this app's control and cannot be deleted from here.

## Your rights

**Export** -- Settings, then "Export your data". You get everything, in a \
machine-readable file.

**Deletion** -- Settings, then "Delete account". This cancels any active \
subscription, erases every document under your account, and then deletes the \
account itself. It is irreversible: afterwards there is nothing left to \
restore, including for us.

If you are in the EU, the UK, or anywhere with comparable law, you can also \
object to processing, ask for a correction, and complain to your data \
protection authority. Write to the address above and it will be acted on.

## Children

This app is not intended for anyone under 16, and data is not knowingly \
collected from anyone under that age. If you believe a child has an account \
here, write and it will be deleted.

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
- Все данные хранятся в дата-центрах Google Cloud на территории Европейского \
союза.
- Всё это можно выгрузить и можно безвозвратно удалить прямо из приложения.

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

**Отчёты о сбоях.** При падении приложения Firebase Crashlytics получает \
модель устройства, версию ОС и трассировку стека. В отладочных сборках это \
отключено.

## Чего не происходит

- Ваши данные не продаются и никогда не продавались.
- Ответы о здоровье не отправляются ни в какую ИИ-модель. Встроенный \
советчик получает только название тренажёра, о котором вы спросили, и язык -- \
больше ничего.
- В приложении нет рекламы, не собирается рекламный идентификатор и не \
встроено ни одного стороннего SDK аналитики или атрибуции.

## Где данные хранятся и кто ещё их касается

Данные лежат в мультирегионе Google Cloud eur3, на территории Европейского \
союза, а серверный код, который их читает, работает в europe-west1. Правила \
безопасности Firestore ограничивают доступ к каждому документу вашей учётной \
записи только вами.

Задействованы два обработчика и никакие другие: Google (Firebase \
Authentication, Firestore, Crashlytics, App Check и модель Gemini) и Stripe \
(платежи).

## Стена поддержки публична -- и только по вашей просьбе

Если вы согласились её показывать, выбранное вами отображаемое имя (до 60 \
символов) и необязательное сообщение (до 200 символов) становятся доступны \
всем. Оставьте имя пустым -- запись будет анонимной. Отказ убирает её. Ничего \
другого о вас не публикуется никогда.

## Сколько данные хранятся

Данные хранятся, пока существует ваша учётная запись, и исчезают, когда вы её \
удаляете. Отдельного таймера хранения нет, архивной копии после удаления не \
остаётся.

Stripe хранит собственные платёжные записи столько, сколько требуют его \
собственные обязательства. Это вне контроля приложения и отсюда не удаляется.

## Ваши права

**Выгрузка** -- «Настройки», затем «Выгрузить мои данные». Вы получаете всё, \
в машиночитаемом файле.

**Удаление** -- «Настройки», затем «Удалить аккаунт». Это отменяет активную \
подписку, стирает все документы вашей учётной записи, а затем удаляет саму \
запись. Действие необратимо: после него восстанавливать нечего, в том числе и \
нам.

Если вы в ЕС, Великобритании или там, где действует сопоставимый закон, вы \
также вправе возразить против обработки, потребовать исправления и подать \
жалобу в свой надзорный орган по защите данных. Напишите по адресу выше -- \
обращение будет отработано.

## Дети

Приложение не предназначено для лиц младше 16 лет, и данные о них осознанно \
не собираются. Если вы считаете, что учётную запись здесь завёл ребёнок, \
напишите -- она будет удалена.

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

You must be at least 16 years old to use the app.

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
exist for -- an equipment report to correct the catalogue, a wall message to \
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

Пользоваться приложением можно с 16 лет.

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
того, для чего они существуют: сообщение о тренажёре -- чтобы поправить \
каталог, сообщение на стене -- чтобы появиться на публичной стене. Не \
отправляйте противоправное и то, на что у вас нет прав.

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
