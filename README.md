# mg

A service that does something

## Сборка

Для запуска процесса сборки достаточно выполнить просто:

    make

Чтобы запустить полученную сборку в режиме разработки и получить стандартный [Erlang shell][1], нужно всего лишь:

    make start

> _Хозяйке на заметку._ При этом используется стандартный Erlang релиз, собранный при помощи [relx][2] в режиме разработчика.

## Документация

Дальнейшую документацию можно почерпнуть, пройдясь по ссылкам в [соответствующем документе](doc/index.md). 

[1]: http://erlang.org/doc/man/shell.html
[2]: https://github.com/erlware/relx

## Хочется ещё сделать

сейчас:

1. переделать хранение в риаке на msgpack
1. гарантии при вызове таймеров
1. EventNotFound (?)
1. сохранение эвента в синк отдельным шагом автомата
1. тэгирование и установка таймера отдельным шагом
1. сохранение эвента в синке идемпотентной операцией
1. удаление машины, старых эвентов, тэгов
1. сделать автоматические ретраи со внешней политикой в машине и в воркере
1. порефакторить таймеры
1. проработать ситуацию с неработающим стораджем и процессром (чтобы ничего не взрывалось)
1. придумать как искать упавшие машины (или не только упавшие, а как вообще искать машины)
1. сделать прокидывание woody контекста по всей цепочке обработки (в том числе при обращении в базу, и логировать все события с контекстом)

потом:

1. кэширование стейта в памяти
1. выгрузка машин при нехватке памяти
1. контроль очереди к машине и к менеджеру
1. сделать хранение эвентов в кэше ets'е в с lru (?)
1. изменения протокола машины (вроде прокидывания range в запросы и ID в процссор) прокинуть в thrift интерфейс

рефакторинг который нужно делать:

1. привести в порядок типы
1. привести в порядок работу с NS
1. перенести в genlib utils
1. вынести automaton часть из mg_machine
1. разбить тесты на разные машины
1. сделать 2 вида тестов: через прослойку в виде трифта и без
1. привести в порядок настройки тестов
1. доработать readme

тесты:

1. сделать стресс-тест

## Вопросы

1. Можно ли получить историю у упавшей машины? Да, можно, т.к. падение машины влияет только на прогресс.


## EventSink

Основная его задача — сохранение сплошного потока эвенотов, для возможности синхронизации баз. Эвенты должны быть total ordered, и должна быть цепочка хэшей для контроля целостности.
Находится отдельно от машин, и может быть подписан на произвольные namespace'ы. Тоже является машиной в отдельном нэймспейсе (чтобы это работало нормально нужно сделать [оптимизации протокола](https://github.com/rbkmoney/damsel/pull/38) и возможно отдельный бэкенд для бд).
Через настройки описываются подписки event_sink'ов на namespace'ы (точнее на машины).
У машины появляется промежуточный стейт для слива в синк.
