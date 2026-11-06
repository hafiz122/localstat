# Public-documentation target for SGPLOT

LocalStat's four SGPLOT chart types target the light **ODS HTML / HTMLBlue** appearance in SAS 9.4. This is a fixed design target for the independent SVG renderer, not a claim that its output matches a licensed SAS run. SAS/GRAPH lists HTMLBlue as the HTML destination's default style; HTML5 uses a different default style, HTMLEncore. [SAS/GRAPH 9.4 Reference, default destination table](https://documentation.sas.com/api/docsets/graphref/9.4/content/graphref.pdf?locale=en).

## Documented behavior to approximate

| Feature | Public SAS 9.4 evidence | LocalStat target |
| --- | --- | --- |
| Graph size | The ODS Graphics default for SGPLOT is 640 × 480 pixels (4:3). | Use a 640 × 480 SVG view box for an unmodified plot. |
| Scatter | The basic Height and Weight example shows small open blue circles and rounded, evenly spaced numeric ticks. | Draw open blue markers and choose readable numeric tick intervals. |
| Series | SERIES connects observations in data order; SAS recommends sorting the input by X. The stock example uses a blue line without point markers. | Preserve observation order, draw one blue line, and omit markers by default. |
| Bars | The default bar width is 0.8 of the available category width; the default baseline is zero. | Use 80% category slots and show a zero baseline. |
| Category order | HBAR and VBAR default to ascending category values. The discrete-axis default is UNFORMATTED order. | Sort underlying category values before placing bars; preserve their values for aggregation. |
| Bar statistic | Without RESPONSE= the default is frequency; with RESPONSE= it is sum. | Keep these defaults and label the response axis with the statistic. |

The chart-size, scatter, series, bar, and category-order details are from the [SAS 9.4 ODS Graphics: Procedures Guide](https://documentation.sas.com/api/docsets/grstatproc/9.4/content/grstatproc.pdf), specifically “About Scatter Plots” (printed p. 31), “About Series Plots” (p. 32), the SERIES statement (p. 1297), HBAR and VBAR statements (pp. 1003 and 1390), and “Controlling the Size of Your Graph” (Chapter 16). The guide's example figures are visual references, not machine-readable reference SVGs for the same LocalStat fixture data.

## Verification boundary

LocalStat has no licensed SAS 9.4M9 reference environment. Local tests can check dataset selection, plotted values, aggregation, observation order, category order, SVG structure, and the documented defaults above. They cannot establish SAS pixel, layout, font, or complete procedure parity. Public guide screenshots are useful for visual review; they do not replace side-by-side output from the same dataset and environment. Keep SGPLOT recorded as `subset` until a lawful reference source and reviewed differential fixtures exist.
