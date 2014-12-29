var GraphsPlotter = Class.$extend({
  __init__: function(element, resultsParser) {
    this.element = element;
    this.resultsParser = resultsParser;
    this.barClickedHandlers = [];
  },

  onBarClicked: function(handler) {
    this.barClickedHandlers.push(handler);
  },

  render: function() {
    var self = this;
    this.element.empty();

    var options = DeepObjectDefaults.merge(this.options(), this.defaultPlotOptions());
    this.element.jqplot([this.data], options);

    this.element.bind('jqplotDataClick',
      function (ev, seriesIndex, pointIndex, data) {
        self.emitBarClicked(pointIndex);
      }
    );
  },

  emitBarClicked: function(pointIndex) {
    _.each(this.barClickedHandlers, function(handler) {
      handler.call(this, pointIndex);
    });
  },

  notifyNewMeasurements: function(measurements) {
    this.load(measurements);
    this.render();
  },

  load: function(measurements) {
    this.measurements = measurements;
    this.data = this.processData();
  },

  defaultPlotOptions: function() {
    var graphWidth = this.element.innerWidth();
    var barMargin = 9;
    var showPointLabels = graphWidth > 300;

    var maxY = (this.daysPerSet() * this.expectedDailyMax());

    // Divide by two since daily maximum is (probably? :) ) not reached
    // every hour of the day.
    if (this.daysPerSet() > 1) {
      maxY = maxY / 2;
    }

    return {
      seriesDefaults:{
        renderer:$.jqplot.BarRenderer,
        rendererOptions: {
          barMargin: barMargin
        },
        pointLabels: {
          show: showPointLabels,
          hideZeros: true

        }
      },
      grid: {
        background: 'white'
      },

      // Show the legend and put it outside the grid, but inside the
      // plot container, shrinking the grid to accomodate the legend.
      // A value of "outside" would not shrink the grid and allow
      // the legend to overflow the container.
      axes: {
        xaxis: {
          ticks: this.ticks(),
          tickOptions: {formatString: '%d'}
        },

        yaxis: {
          min: 0,
          max: maxY,
          tickOptions: {formatString: '%d'}
        }
      }
    };
  },

  ticks: function() {
    // Can specify a custom tick Array.
    // Ticks should match up one for each y value (category) in the series.
    var startIndex = this.resultsParser.periodStartIndex();

    return _.range(startIndex - 1, this.resultsParser.singlePeriod(this.measurements)+startIndex+1);
  },

  daysPerSet: function() {
    return this.resultsParser.approxDaysPerPeriod();
  }
});

var StroomPlotter = GraphsPlotter.$extend({
  expectedDailyMax: function() { return 1500; },
  processData: function() {
    var parsedStroomTotaal = this.resultsParser.parse(this.measurements, "stroom_totaal");
    var stroomRelative = RelativeConverter().convert(parsedStroomTotaal);

    return _.map(stroomRelative, function(kwh) { return kwh*1000; });
  },

  options: function() {
    return {
      // Custom labels for the series are specified with the "label"
      // option on the series option.  Here a series option object
      // is specified for each series.
      series:[
        {label:'Stroom', color: '#428bca'}
      ],
      axes: {
        yaxis: {
          tickOptions: {formatString: '%d'},
        }
      }
    };
  },
});

var GasPlotter = GraphsPlotter.$extend({
  expectedDailyMax: function() { return 1200; },
  processData: function() {
    var gas = this.resultsParser.parse(this.measurements, "gas");
    var gasRelative = RelativeConverter().convert(gas);

    return _.map(gasRelative, function(m3) { return m3*1000; });
  },

  options: function() {
    return {
      series: [
        { label: 'Gas', color: '#f0ad4e'}
      ],
      axes: {
        yaxis: {
        }
      }
    };
  }
});