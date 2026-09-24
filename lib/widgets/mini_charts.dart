import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Widgets de gráficas reutilizables para la pestaña "Gráficas" de
/// Auditoría. Cada builder recibe una [height] para poder usarse tanto en
/// la tarjeta chica del listado como en la pantalla de enfoque, sin
/// duplicar la lógica de dibujo.

/// Redondea [valor] hacia arriba al siguiente "número limpio" (1, 2, 5 o 10
/// multiplicado por una potencia de 10: ..., 10, 20, 50, 100, 200, 500...).
/// Se usa para que el paso entre marcas del eje siempre divida exacto al
/// máximo del eje — si no, fl_chart agrega una marca extra pegada al techo
/// para marcar el valor máximo real, y esa marca casi siempre queda tan
/// cerca de la última marca "normal" que se superponen visualmente.
double _pasoLimpio(double valor) {
  if (valor <= 0) return 1;
  final potencia = math.pow(10, (math.log(valor) / math.ln10).floor()).toDouble();
  final normalizado = valor / potencia;
  double pasoNormalizado;
  if (normalizado <= 1) {
    pasoNormalizado = 1;
  } else if (normalizado <= 2) {
    pasoNormalizado = 2;
  } else if (normalizado <= 5) {
    pasoNormalizado = 5;
  } else {
    pasoNormalizado = 10;
  }
  return pasoNormalizado * potencia;
}

String abreviarMonto(double valor) {
  final signo = valor < 0 ? '-' : '';
  final v = valor.abs();
  if (v >= 1000000) return '$signo\$${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '$signo\$${(v / 1000).toStringAsFixed(1)}K';
  return '$signo\$${v.toStringAsFixed(0)}';
}

/// Barra simple: una barra por categoría (usada para "capital nuevo por
/// mes" y para "cuotas por vencimiento"). [esMoneda] controla si el eje Y
/// se formatea como dinero abreviado o como número entero.
Widget buildBarraCategorica({
  required List<String> etiquetas,
  required List<double> valores,
  Color color = Colors.black,
  List<Color>? coloresPorBarra,
  required double height,
  bool esMoneda = true,
}) {
  final maxValor = valores.isEmpty ? 0.0 : valores.reduce((a, b) => a > b ? a : b);
  final paso = _pasoLimpio((maxValor <= 0 ? 1.0 : maxValor * 1.2) / 5);
  final maxEje = paso * 5;

  return SizedBox(
    height: height,
    child: BarChart(
      BarChartData(
        maxY: maxEje,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: paso,
              getTitlesWidget: (value, meta) => Text(
                esMoneda ? abreviarMonto(value) : value.toInt().toString(),
                textScaler: TextScaler.noScaling,
                style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= etiquetas.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    etiquetas[i],
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade800),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(valores.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: valores[i],
                color: coloresPorBarra != null ? coloresPorBarra[i] : color,
                width: 18,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }),
      ),
    ),
  );
}

/// Barra agrupada: varias series (colores) por cada etiqueta del eje X.
/// [series] es nombre de la serie -> lista de valores (mismo largo que
/// [etiquetas]); [colores] es nombre de la serie -> color.
Widget buildBarraAgrupada({
  required List<String> etiquetas,
  required Map<String, List<double>> series,
  required Map<String, Color> colores,
  required double height,
}) {
  final todos = series.values.expand((v) => v).toList();
  final maxValor = todos.isEmpty ? 0.0 : todos.reduce((a, b) => a > b ? a : b);
  final paso = _pasoLimpio((maxValor <= 0 ? 1.0 : maxValor * 1.2) / 5);
  final maxEje = paso * 5;
  final nombresSeries = series.keys.toList();

  return SizedBox(
    height: height,
    child: BarChart(
      BarChartData(
        maxY: maxEje,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: paso,
              getTitlesWidget: (value, meta) => Text(
                abreviarMonto(value),
                textScaler: TextScaler.noScaling,
                style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= etiquetas.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    etiquetas[i],
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade800),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(etiquetas.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: nombresSeries.map((nombre) {
              return BarChartRodData(
                toY: series[nombre]![i],
                color: colores[nombre],
                width: 9,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              );
            }).toList(),
            barsSpace: 3,
          );
        }),
      ),
    ),
  );
}

/// Dona (pie con hueco al centro) para distribuciones por categoría.
/// [datos] es etiqueta -> valor; [colores] es etiqueta -> color.
Widget buildDona({
  required Map<String, num> datos,
  required Map<String, Color> colores,
  required double height,
}) {
  final total = datos.values.fold<num>(0, (a, b) => a + b);

  return SizedBox(
    height: height,
    child: PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: height * 0.22,
        sections: datos.entries.where((e) => e.value > 0).map((e) {
          final porcentaje = total == 0 ? 0 : (e.value / total * 100);
          return PieChartSectionData(
            value: e.value.toDouble(),
            color: colores[e.key] ?? Colors.grey,
            title: '${porcentaje.toStringAsFixed(0)}%',
            radius: height * 0.28,
            titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          );
        }).toList(),
      ),
    ),
  );
}

/// Leyenda simple de color + etiqueta, usada debajo de las gráficas con
/// más de una serie/categoría.
Widget buildLeyenda(Map<String, Color> colores) {
  return Wrap(
    spacing: 14,
    runSpacing: 6,
    children: colores.entries.map((e) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: e.value, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(e.key, style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w500)),
        ],
      );
    }).toList(),
  );
}
