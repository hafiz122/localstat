                let headerHeights = table.headers.map { rowHeight($0, columns: columns, widths: widths, header: true) }
                let headerHeight = headerHeights.reduce(CGFloat(0), +)
                let rowHeights = contentRows.map { rowHeight($0, columns: columns, widths: widths, header: false) }
