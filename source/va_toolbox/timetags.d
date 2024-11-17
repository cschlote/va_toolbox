/** Implementation of time-based version tuple
 *
 * This module creates a version tuple from the current date.
 *
 * Authors: Carsten Schlote
 * Copyright: Carsten Schlote, 2024
 * License: GPL-3.0-only
 */
module va_toolbox.timetags;

import std.datetime.date;
import std.datetime.systime;

/** Create a time-tag string from a systime value
 *
 * Param:
 *   currtime - system time or current system time as default
 * Returns:
 *   a version string of the form:
 *   <yea since 2000>.<weekOfYear>.<0000..9999>
 */
string getTimeTagString(SysTime currtime = Clock.currTime()) {
	import core.time : weeks;
	import std.conv : to;
	import std.datetime.interval : Interval;
	import std.format : format;

	/* Create the start time of isoWeek starting at midnight of first day */
	const auto startOfIsoWeekSysTime = SysTime(startOfIsoWeek(cast(Date) currtime));

	/* Calculate the number of minutes since start of isoWeek */
	const auto usedMinutesPerWeek =
		Interval!SysTime(startOfIsoWeekSysTime, currtime)
			.length.total!"minutes";

	/* A week is divided into 100 units - calc minutes per unit */
	const auto unitMinutesPerWeek = weeks(1).total!"minutes" / cast(double) 10_000;

	/* Now divide used minutes by unit-minutes */
	const auto weekFraction = usedMinutesPerWeek / unitMinutesPerWeek;

	/* Create a version string as def'd above , substract 2 milleniums */
	auto fwVersion = format("%d.%d.%04d",
		currtime.year - 2000,
		(cast(Date) currtime).steadyIsoWeek,
		weekFraction.to!ulong);

	return fwVersion;
}

@("getTimeTagString")
unittest {
	assert("19.14.0000" == getTimeTagString(SysTime(DateTime(2019, 4, 1, 0, 0, 0))), "Test 1");
	assert("19.14.6567" == getTimeTagString(SysTime(DateTime(2019, 4, 5, 14, 20, 0))), "Test 2");
	assert("19.15.0000" == getTimeTagString(SysTime(DateTime(2019, 4, 8, 0, 0, 0))), "Test 3");
	assert("19.15.9999" == getTimeTagString(SysTime(DateTime(2019, 4, 14, 23, 59, 59))), "Test 4");
}

/* ----------------------------------------------------------------------- */

/** european dayOfWeek enumeration (Monday = 0 .. Sunday = 6)
 *
 * Note: DaysOfWeek starts at Sunday, not on Monday. This is a difference between
 *       european and anglo-american countries.
 */
enum DayOfIsoWeek {
	mon,
	tue,
	wed,
	thu,
	fri,
	sat,
	sun
}

/** get the european dayOfWeek enumeration (Monday = 0 .. Sunday = 6)
 *
 * Return the current day of a an isoWeek in european notation starting at
 * at monday. The weekend includes saturday and sunday in Europe.
 *
 * Param:
 *   data - either a Date, DateTime or any other type providing a 'dayOfWeek'
 *           property.
 * Returns:
 *   The isoWeek starting from 1 to 53
 * Note: DaysOfWeek starts at Sunday, not on Monday. This is a difference between
 *       european and anglo-american countries.
 */
pure nothrow @nogc @property @safe DayOfIsoWeek dayOfIsoWeek(T)(T data) {
	DayOfWeek stddow = data.dayOfWeek; // Get the american enumeration
	if (stddow == DayOfWeek.sun)
		return DayOfIsoWeek.sun;
	else
		return cast(DayOfIsoWeek)(stddow - 1);
}

@("dayOfIsoWeek")
unittest {
	void test(T)() {
		assert(dayOfIsoWeek(T(2016, 2, 29)) == DayOfIsoWeek.mon, "2016.Feb.29 is a monday");
		assert(dayOfIsoWeek(T(2018, 12, 24)) == DayOfIsoWeek.mon, "2018.Dec.24 is a monday");
		assert(dayOfIsoWeek(T(2018, 12, 30)) == DayOfIsoWeek.sun, "2018.Dec.30 is a sunday");
		assert(dayOfIsoWeek(T(2018, 12, 31)) == DayOfIsoWeek.mon, "2018.Dec.31 is a monday");
		assert(dayOfIsoWeek(T(2019, 1, 8)) == DayOfIsoWeek.tue, "2019.Jan.8 is a monday");
		assert(dayOfIsoWeek(T(2019, 4, 1)) == DayOfIsoWeek.mon, "2019.Apr.1 is a monday");
		assert(dayOfIsoWeek(T(2019, 11, 19)) == DayOfIsoWeek.tue, "2018.Dec.31 is a sunday");
		assert(dayOfIsoWeek(T(2019, 12, 31)) == DayOfIsoWeek.tue, "2019.Dec.31 is a tuesday");
		assert(dayOfIsoWeek(T(2020, 2, 29)) == DayOfIsoWeek.sat, "2020.Feb.29 is a saturday");
	}

	test!Date();
	test!DateTime();
}

/** modifyed steady isoWeek (ranging from 0 to 53 weeks)
 *
 * Return a modified isoWeek value, which is monotonically increasing with the
 * supplied date. The built-in isoWeek based on ISO8601 sometimes already uses
 * the number 1 for the last days of the last week in the following cases, e.g.:
 *
 * Example 1 :
 * 2019-Dec-30 : Result of isoWeek 01 differs from steadyIsoWeek 53 -> 0.19.53.0
 * 2019-Dec-31 : Result of isoWeek 01 differs from steadyIsoWeek 53 -> 0.19.53.14
 *
 * Example 2:

 * 2021-Jan-01 : Result of isoWeek 53 differs from steadyIsoWeek 00 -> 0.21.0.57
 * 2021-Jan-02 : Result of isoWeek 53 differs from steadyIsoWeek 00 -> 0.21.0.71
 * 2021-Jan-03 : Result of isoWeek 53 differs from steadyIsoWeek 00 -> 0.21.0.85
 *
 * So the isoWeek number 1 is returned twice: On time at the bin o the year,
 * and a second time at the end of the year.
 *
 * This would break comparisions of time-tag version tags. So these cases are
 * fixed up to return week 53 for these remaining days at the end of a year.
 *
 * So Date(2018-Dec-31) doesn't return the same value as Date(2018-Jan-01)-
 * Date(2018-Jan-07), but 53 instead. So ordered compares will evaluate into
 * the correct result.
 *
 * Same logic applies for an isoWeek number of 53 at the beginning of a year.
 * In this cases the value is set to 0. So again values can be compared and
 * result in senseful results.
 *
 * Param:
 *   data - either a Date, DateTime or any other type providing a 'isoWeek'
 *           property.
 * Returns:
 *   The isoWeek starting from 0 to 53
 */
pure nothrow @property @safe steadyIsoWeek(T)(T data) {
	auto isoweek = data.isoWeek; // Get the built-in isoWeek number
	if ((data.month == 12) && (isoweek == 1))
		isoweek = 53;
	else if ((data.month == 1) && (isoweek == 53))
		isoweek = 0;
	return isoweek;
}

@("steadyIsoWeek 1")
unittest {
	void test(T)() {
		// writeln("\t.. with type ", T.stringof);
		assert(steadyIsoWeek(T(2016, 2, 29)) == 9, "2016.Feb.29 is week  9");
		assert(steadyIsoWeek(T(2018, 12, 24)) == 52, "2018.Dec.24 is week 52");
		assert(steadyIsoWeek(T(2018, 12, 30)) == 52, "2018.Dec.30 is week 52");
		assert(steadyIsoWeek(T(2018, 12, 31)) == 53, "2018.Dec.31 is week 53");
		assert(steadyIsoWeek(T(2019, 1, 8)) == 2, "2018.Dec.24 is week  2");
		assert(steadyIsoWeek(T(2019, 4, 1)) == 14, "2018.Dec.24 is week 14");
		assert(steadyIsoWeek(T(2019, 11, 19)) == 47, "2018.Dec.24 is week 47");
		assert(steadyIsoWeek(T(2019, 12, 31)) == 53, "2019.Dec.31 is week 53");
		assert(steadyIsoWeek(T(2020, 2, 29)) == 9, "2020.Feb.29 is week  9");
		assert(steadyIsoWeek(T(2021, 1, 01)) == 0, "2020.Feb.29 is week  9");
	}

	test!Date();
	test!DateTime();
}

@("steadyIsoWeek 2")
unittest {
	void test(T)() {
		struct TestVal {
			T date;
			int iso, steadyiso;
		}

		static const TestVal[] testvals = [
			{Date(2016, 1, 1), 53, 0},
			{Date(2016, 1, 2), 53, 0},
			{Date(2016, 1, 3), 53, 0},
			{Date(2018, 12, 31), 1, 53},
			{Date(2019, 12, 30), 1, 53},
			{Date(2019, 12, 31), 1, 53},
			{Date(2021, 1, 1), 53, 0},
			{Date(2021, 1, 2), 53, 0},
			{Date(2021, 1, 3), 53, 0},
			{Date(2024, 12, 30), 1, 53},
			{Date(2024, 12, 31), 1, 53}
		];

		T date;
		static foreach (e; testvals) {
			date = e.date;
			assert(date.isoWeek == e.iso);
			assert(date.steadyIsoWeek == e.steadyiso);
		}
	}

	test!Date();
	test!DateTime();
}

/** get the first day of the isoWeek starting at midnight
 *
 * Sometimes we need to know the first day of an isoWeek, e.g. to calculate
 * the duration from/to the beginning of a given isoWeek.
 *
 * Param:
 *   date - either an Date, DateTime or any other type providing a 'isoWeek'
 *           property.
 * Returns:
 *   The starting day at midnight for the isoWeek specified by data
 */
@property @safe T startOfIsoWeek(T)(T date) {
	/* Get the weekday starting from 0 (monday), then substract according
       number of days to get the startday. */
	int offset = dayOfIsoWeek(date);
	auto rc = date;
	if (offset != 0) {
		if ((date.day - offset) < 1) // Would wrap into previous month?
		{
			// Remember number of days to substract in previous month
			const int numberOfDaysLeft = offset - date.day;
			rc.add!"months"(-1);
			rc.day = SysTime(rc).daysInMonth;
			rc.roll!"days"(-(numberOfDaysLeft));
		} else {
			rc.roll!"days"(-(offset));
		}
	}
	return rc;
}

@("startOfIsoWeek")
unittest {
	// writeln("Testing startOfIsoWeek function ...");
	void test(T)() {
		// writeln("\t.. with type ", T.stringof);
		assert(startOfIsoWeek(T(2016, 2, 29)) == T(2016, 2, 29), "2016, Week  9 started on (2016, 2,29)");
		assert(startOfIsoWeek(T(2018, 12, 24)) == T(2018, 12, 24), "2018, Week 52 started on (2018,12,24)");
		assert(startOfIsoWeek(T(2018, 12, 30)) == T(2018, 12, 24), "2018, Week 52 started on (2018,12,24)");
		assert(startOfIsoWeek(T(2018, 12, 31)) == T(2018, 12, 31), "2018, Week 53 started on (2018,12,31)");
		assert(startOfIsoWeek(T(2019, 1, 8)) == T(2019, 1, 7), "2019, Week  2 started on (2019, 1, 7)");
		assert(startOfIsoWeek(T(2019, 4, 1)) == T(2019, 4, 1), "2019, Week 14 started on (2019, 4, 1)");
		assert(startOfIsoWeek(T(2019, 11, 19)) == T(2019, 11, 18), "2019, Week 47 started on (2019,11,18)");
		assert(startOfIsoWeek(T(2019, 12, 31)) == T(2019, 12, 30), "2019, Week 53 started on (2019,12,30)");
		assert(startOfIsoWeek(T(2020, 2, 29)) == T(2020, 2, 24), "2020, Week  9 started on (2020, 2,24)");
		assert(startOfIsoWeek(T(2020, 12, 1)) == T(2020, 11, 30), "2020, Week 49 started on (2020,11,30)");
		assert(startOfIsoWeek(T(2021, 1, 3)) == T(2020, 12, 28), "2021, Week 53 started on (2020,12,28)");
	}

	test!Date();
	test!DateTime();
}

/* ----------------------------------------------------------------------- */

/* Loop over some extended period of time and compare expected values
 * against the calculated ones.
 */
@("timetag: Generic tests over range of date/time.")
unittest {
	import core.time : dur;
	import std.conv : to;
	import std.format : format;

	Date date = Date(2015, 12, 28);
	assert(date.dayOfIsoWeek == DayOfIsoWeek.mon, "Loop shall start on a monday.");

	const Date enddate = Date(2025, 1, 12);
	assert(enddate.dayOfIsoWeek == DayOfIsoWeek.sun, "Loop shall on a sunday.");

	// writefln("\t.. compare expected values for dayOfIsoWeek and startOfIsoWeek");
	int expDayOfWeek = 0;
	Date expStartOfWeek = date;
	while (date <= enddate) // Ends on a sunday
	{
		assert(date.dayOfIsoWeek == expDayOfWeek, format("Error: Expected day of week ", expDayOfWeek));
		assert(date.startOfIsoWeek == expStartOfWeek, format("Error: Expected start of week ", expStartOfWeek));

		/* Increment values to next date to test and expected values */
		date += dur!"days"(1);
		expDayOfWeek = (expDayOfWeek + 1) % 7;
		if (expDayOfWeek == 0)
			expStartOfWeek += dur!"days"(7);
	}
}
