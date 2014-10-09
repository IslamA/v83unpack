﻿
Перем мНастройки; // соответствие настроек скрипта
Перем мПредыдущиеСвойстваИБ; // Состояния флагов блокировки ИБ до начала выполнения скрипта
Перем мВыдаватьСообщенияСборки;

////////////////////////////////////////////////////////////////////////////
// Программный интерфейс

Процедура Инициализация() Экспорт
	
	Если мНастройки = Неопределено Тогда
		
		Отладка = Ложь;
		Если Отладка Тогда // Отладочный запуск вне билд-сервера
			мНастройки = Новый Структура;
			
			мНастройки.Вставить("ИмяСервера", "WS-MSK-A2981");
			мНастройки.Вставить("АдминистраторКластера", "");
			мНастройки.Вставить("ПарольАдминистратораКластера", "");
			мНастройки.Вставить("КлассCOMСоединения", "V83.ComConnector");
			
			// Параметры рабочей базы
			мНастройки.Вставить("ИмяБазы", "srv");
			мНастройки.Вставить("АдминистраторБазы", "");
			мНастройки.Вставить("ПарольАдминистратораБазы", "");
			
			// Прочие настройки
			мНастройки.Вставить("СообщениеБлокировки", "");
			мНастройки.Вставить("ТаймаутБлокировки", 1);
		Иначе
			ПрочитатьНастройки();
			ПроверитьОбязательныеНастройки();
		КонецЕсли;
	
		мВыдаватьСообщенияСборки = Истина;
	КонецЕсли;
	
КонецПроцедуры

Функция ДескрипторУправленияСеансамиБазы() Экспорт
	
	Перем ComConnector;
	Перем ServerAgent;
	Перем Clusters;
	
	Инициализация();
	
	Дескриптор = Новый Структура;
	Дескриптор.Вставить("ServerAgent", Неопределено);
	Дескриптор.Вставить("Cluster", Неопределено);
	Дескриптор.Вставить("ConnectToWorkProcess", Неопределено);
	Дескриптор.Вставить("InfoBase", Неопределено);
	
	ИмяСервера = мНастройки.ИмяСервера;
	ComConnector = ПолучитьСоединениеСКластером();

	Попытка
	
		СообщениеСборки("Подключение к агенту сервера");
		ServerAgent = ComConnector.ConnectAgent(ИмяСервера);
		Дескриптор.ServerAgent = ServerAgent;
		
		СообщениеСборки("Получение массива кластеров сервера у агента сервера");
		Clusters = ServerAgent.GetClusters();
		
		Cluster = НайтиКластерСерверов(Clusters, ИмяСервера);
		СообщениеСборки("Аутентикация к найденному кластеру: " + Cluster.ClusterName + ", "+Cluster.HostName);
		ServerAgent.Authenticate(Cluster, мНастройки.АдминистраторКластера, мНастройки.ПарольАдминистратораКластера);
			
		Дескриптор.Cluster = Cluster;
		Дескриптор.ConnectToWorkProcess = ПолучитьСоединениеСПроцессом(ComConnector, ServerAgent, Cluster);
		
		Если Дескриптор.ConnectToWorkProcess <> Неопределено Тогда
			InfoBase = НайтиИнформационнуюБазуВРабочемПроцессе(Дескриптор.ConnectToWorkProcess);
			Если Infobase = Неопределено Тогда
				ВызватьИсключение "Не нашли нужную ИБ";
			КонецЕсли;
			
			Дескриптор.InfoBase = InfoBase;
			
		Иначе
			ВызватьИсключение "Нет запущенных рабочих процессов";
		КонецЕсли;
		
	Исключение

		ЗакрытьДескриптор(Дескриптор);
		ОсвободитьОбъектКластера(Clusters);
		ОсвободитьОбъектКластера(ComConnector);
		
		ВызватьИсключение;
		
	КонецПопытки;
	
	Возврат Дескриптор;
	
КонецФункции

Процедура ЗакрытьДескриптор(Знач Дескриптор) Экспорт

	ОсвободитьОбъектКластера(Дескриптор.ConnectToWorkProcess);
	ОсвободитьОбъектКластера(Дескриптор.Cluster);
	ОсвободитьОбъектКластера(Дескриптор.ServerAgent);
	ОсвободитьОбъектКластера(Дескриптор.InfoBase);

КонецПроцедуры

Функция Опция(Знач ИмяОпции) Экспорт
	
	Возврат мНастройки[ИмяОпции];
	
КонецФункции

Процедура ЗаблокироватьСоединенияСБазой(Знач Дескриптор) Экспорт
	
	InfoBase = Дескриптор.InfoBase;
	
	СообщениеСборки("Установка запрета на подключения к ИБ: " + InfoBase.Name);
	
    InfoBase.ConnectDenied = Истина;
    InfoBase.ScheduledJobsDenied = Истина;
    InfoBase.DeniedMessage = мНастройки.СообщениеБлокировки;
    InfoBase.PermissionCode = мНастройки.ПарольАдминистратораБазы;
	
	Попытка
		Дескриптор.ConnectToWorkProcess.UpdateInfoBase(InfoBase);
	Исключение
		
		ТекстОшибки = ИнформацияОбОшибке().Описание;
		СообщениеСборки("Не удалось заблокировать подключения: <" + ТекстОшибки + "> Попытка восстановления...");
		
		ВызватьИсключение;
		
	КонецПопытки;
	
КонецПроцедуры

Процедура ПрекратитьСуществующиеСеансы(Знач Дескриптор) Экспорт
	
	СообщениеСборки("Отключение сеансов информационной базы");
	InfobaseDescriptor = НайтиДескрипторИнформационнойБазы(Дескриптор.ServerAgent, Дескриптор.Cluster);
	СообщениеСборки("Обработка списка сеансов");
	
	Sessions = Дескриптор.ServerAgent.GetInfoBaseSessions(Дескриптор.Cluster, InfobaseDescriptor);
    Для Сч = 0 По Sessions.Количество()-1 Цикл
        Session  = Sessions[Сч];
        UserName = Session.UserName;
        AppID    = ВРег(Session.AppID);
		
        СообщениеСборки("Попытка отключения: " + "User=["+UserName+"] ConnID=["+""+"] AppID=["+AppID+"]");
        Дескриптор.ServerAgent.TerminateSession(Дескриптор.Cluster, Session);
		ОсвободитьОбъектКластера(Session);
		СообщениеСборки("Выполнено");
	КонецЦикла;
	
	ОсвободитьОбъектКластера(InfobaseDescriptor);
	СообщениеСборки("Сеансы завершены");
	
КонецПроцедуры

Процедура РазблокироватьСоединенияСБазой(Знач Дескриптор, Знач СтатусБлокировки = Ложь, Знач СтатусРегЗаданий = Ложь) Экспорт
	
	Если Дескриптор.InfoBase = Неопределено Тогда
		Дескриптор.InfoBase = НайтиИнформационнуюБазуВРабочемПроцессе(Дескриптор.ConnectToWorkProcess);
		Если Дескриптор.Infobase = Неопределено Тогда
			ВызватьИсключение "Не нашли нужную ИБ при попытке восстановления блокировки";
		КонецЕсли;
	КонецЕсли;
	
	Попытка
		Дескриптор.InfoBase.ConnectDenied = СтатусБлокировки;
		Дескриптор.InfoBase.ScheduledJobsDenied = СтатусРегЗаданий;
		Дескриптор.InfoBase.DeniedMessage = "";
		Дескриптор.InfoBase.PermissionCode = "";
		Дескриптор.ConnectToWorkProcess.UpdateInfoBase(Дескриптор.InfoBase);
		СообщениеСборки("Соединения с информационной базой разрешены: " + Дескриптор.InfoBase.Name);
	Исключение
		СообщениеСборки("Не удалось восстановить опции блокировки:" + ИнформацияОбОшибке().Описание);
		ВызватьИсключение;
	КонецПопытки;
	
КонецПроцедуры

Функция ЕстьРаботающиеСеансы(Знач Дескриптор, Знач ТихаяПроверка = Ложь, Знач ИгнорироватьКонсольКластера = Истина) Экспорт
	
	ТекРежимВыдачиСообщений = мВыдаватьСообщенияСборки;
	мВыдаватьСообщенияСборки = Не ТихаяПроверка;

	Попытка
		InfobaseDescriptor = НайтиДескрипторИнформационнойБазы(Дескриптор.ServerAgent, Дескриптор.Cluster);
		Сеансы = Дескриптор.ServerAgent.GetInfoBaseSessions(Дескриптор.Cluster, InfobaseDescriptor);
		ЕстьСеансы = Ложь;
		Для Каждого Сеанс Из Сеансы Цикл
			AppID = Строка(Сеанс.AppID);
			ОсвободитьОбъектКластера(Сеанс);
			Если ВРег(AppID) <> "COMCONSOLE" Тогда
				ЕстьСеансы = Истина;
				Прервать;
			ИначеЕсли Не ИгнорироватьКонсольКластера Тогда
				ЕстьСеансы = Истина;
				Прервать;
			КонецЕсли;
		КонецЦикла;
		
		ОсвободитьОбъектКластера(InfobaseDescriptor);
	Исключение
		мВыдаватьСообщенияСборки = ТекРежимВыдачиСообщений;
		ВызватьИсключение;
	КонецПопытки;
	
	мВыдаватьСообщенияСборки = ТекРежимВыдачиСообщений;
	Возврат ЕстьСеансы;
	
КонецФункции

////////////////////////////////////////////////////////////////////////////
// Инициализация скрипта

Процедура ПрочитатьНастройки()
	
	мНастройки = Новый Структура;
	СИ = Новый СистемнаяИнформация();
	
	Окружение = СИ.ПеременныеСреды();
	
	// Параметры сервера
	мНастройки.Вставить("ИмяСервера", Окружение["server_host"]);
	мНастройки.Вставить("АдминистраторКластера", Окружение["cluster_admin"]);
	мНастройки.Вставить("ПарольАдминистратораКластера", Окружение["cluster_admin_password"]);
	мНастройки.Вставить("КлассCOMСоединения", Окружение["com_connector"]);
	
	// Параметры рабочей базы
	мНастройки.Вставить("ИмяБазы", Окружение["db_name"]);
	мНастройки.Вставить("АдминистраторБазы", Окружение["db_user"]);
	мНастройки.Вставить("ПарольАдминистратораБазы", Окружение["db_password"]);
	
	// Прочие настройки
	мНастройки.Вставить("СообщениеБлокировки", Окружение["lock_message"]);
	мНастройки.Вставить("ТаймаутБлокировки", Окружение["lock_timeout"]);
	
	Если мНастройки.ТаймаутБлокировки = Неопределено Тогда
		мНастройки.ТаймаутБлокировки = 1000;
	КонецЕсли;
	
КонецПроцедуры

Процедура ПроверитьОбязательныеНастройки()
	
	Если ПустаяСтрока(мНастройки.КлассCOMСоединения) Тогда
		ВызватьИсключение "Не задан класс COM-соединения";
	КонецЕсли;
	
	Если ПустаяСтрока(мНастройки.ИмяСервера) Тогда
		ВызватьИсключение "Не задано имя сервера приложений 1С";
	КонецЕсли;
	
	Если ПустаяСтрока(мНастройки.ИмяБазы) Тогда
		ВызватьИсключение "Не задано имя базы данных 1С";
	КонецЕсли;
	
КонецПроцедуры


////////////////////////////////////////////////////////////////////////////
// Основная полезная нагрузка

Функция ПолучитьСоединениеСКластером()
	
	Соединение = мНастройки.КлассCOMСоединения;
	СообщениеСборки("Создание COM-коннектора <"+ Соединение + ">");
	
	Возврат Новый COMОбъект(Соединение);
	
КонецФункции

Функция НайтиКластерСерверов(Знач Clusters, Знач ИмяСервера)
	
	НашлиКластер = Ложь;
	Для i = 0 По Clusters.Количество()-1 Цикл
		Cluster = Clusters[i];
		Если ВРег(Cluster.HostName) = ВРег(ИмяСервера) Тогда
			НашлиКластер = Истина;
			Прервать;
		КонецЕсли;
		
	КонецЦикла;
	
	Если Не НашлиКластер Тогда
		ОсвободитьОбъектКластера(Cluster);
		ВызватьИсключение "Ошибка - не нашли кластер <"+ИмяСервера+">";
	КонецЕсли;
	
	Возврат Cluster;
	
КонецФункции

Функция ПолучитьСоединениеСПроцессом(Знач ComConnector, Знач ServerAgent, Знач Cluster)

	Перем СоединениеСПроцессом;

	Попытка
		
		СообщениеСборки("Получение списка работающих рабочих процессов и обход в цикле");
			
		WorkingProcesses = ServerAgent.GetWorkingProcesses(Cluster);
			
		Для j = 0 To WorkingProcesses.Количество()-1 Цикл

			Если WorkingProcesses[j].Running = 1 Тогда
				
				СтрокаСоединения = "tcp://" + WorkingProcesses[j].HostName + ":" + WorkingProcesses[j].MainPort;
				СообщениеСборки("Создание соединения с рабочим процессом " + СтрокаСоединения);
				ConnectToWorkProcess = ComConnector.ConnectWorkingProcess(СтрокаСоединения);
				
				ConnectToWorkProcess.AuthenticateAdmin(мНастройки.АдминистраторКластера, мНастройки.ПарольАдминистратораКластера);
				ConnectToWorkProcess.AddAuthentication(мНастройки.АдминистраторБазы, мНастройки.ПарольАдминистратораБазы);
				
				СоединениеСПроцессом = ConnectToWorkProcess;
				Прервать;
				
			КонецЕсли;
			
		КонецЦикла;
		
	Исключение
		
		ОсвободитьОбъектКластера(ConnectToWorkProcess);
		ОсвободитьОбъектКластера(WorkingProcesses);
		
		ВызватьИсключение;
		
	КонецПопытки;
	
	ОсвободитьОбъектКластера(WorkingProcesses);
	
	Возврат СоединениеСПроцессом;

КонецФункции

Функция НайтиДескрипторИнформационнойБазы(Знач ServerAgent, Знач Cluster)
	
	СообщениеСборки("Поиск нужной ИБ для сессии");
	Возврат НайтиИнформационнуюБазуВКоллекции(ServerAgent.GetInfoBases(Cluster));
	
КонецФункции

Функция НайтиИнформационнуюБазуВРабочемПроцессе(Знач ConnectToWorkProcess)
	
	СообщениеСборки("Получение списка ИБ рабочего процесса");
	Возврат НайтиИнформационнуюБазуВКоллекции(ConnectToWorkProcess.GetInfoBases());
	
КонецФункции

Функция НайтиИнформационнуюБазуВКоллекции(Знач InfoBases)
	
	Перем InfoBase;
	
	Попытка
		ИскомаяИБ = мНастройки.ИмяБазы;
		БазаНайдена = Ложь;
		
		InfoBase = ОбойтиКоллекциюИНайтиИБ(InfoBases, ИскомаяИБ);
		
		БазаНайдена = InfoBase <> Неопределено;
		
	Исключение
		ОсвободитьОбъектКластера(InfoBase);
		ОсвободитьОбъектКластера(InfoBases);
		ВызватьИсключение;
	КонецПопытки;
	
	Если Не БазаНайдена Тогда
		InfoBase = Неопределено;
	КонецЕсли;
	
	ОсвободитьОбъектКластера(InfoBases);
	
	Возврат InfoBase;
	
КонецФункции

Функция ОбойтиКоллекциюИНайтиИБ(Знач InfoBases,Знач ИскомаяИБ)
	
	Перем InfoBase;
	СообщениеСборки("Поиск ИБ " + ИскомаяИБ);
    Для Каждого InfoBase Из InfoBases Цикл
        СообщениеСборки(" Обрабатывается ИБ: " + InfoBase.Name);
        Если НРег(InfoBase.Name) = НРег(ИскомаяИБ) Then
            БазаНайдена = Истина;
            СообщениеСборки(" Нашли нужную ИБ");
            Прервать;
		КонецЕсли;
	КонецЦикла;
	
	Если Не БазаНайдена Тогда
		ОсвободитьОбъектКластера(InfoBase);
	КонецЕсли;
	
	Возврат InfoBase;
	
КонецФункции


////////////////////////////////////////////////////////////////////////////
// Служебные процедуры

Процедура СообщениеСборки(Знач Сообщение)

	Если мВыдаватьСообщенияСборки Тогда
		Сообщить(Строка(ТекущаяДата()) + " " + Сообщение);
	КонецЕсли;
	
КонецПроцедуры

Процедура ОсвободитьОбъектКластера(Соединение)
	
	Если Соединение <> Неопределено Тогда
		ОсвободитьОбъект(Соединение);
		Соединение = Неопределено;
	КонецЕсли;
	
КонецПроцедуры
