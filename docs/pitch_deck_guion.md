# Guion Oficial del Pitch: NexoLlano 🌾📲
**Convocatoria de Innovación Abierta CREATIC Casanare**  
*Gobernación de Casanare – Dirección TIC / EON CASANARE S.A.S.*  
**Tiempo estimado:** 4 a 5 minutos + 3 minutos de preguntas del jurado evaluador.

---

## ⏱️ Minuto 0:00 - 0:45 | El Gancho y el Dolor Local de Casanare

> *"Buenos días, señores miembros del jurado y equipo de CREATIC Casanare.*  
> *¿Saben cómo llevan el inventario hoy en día Don Pedro en su tienda de barrio en Yopal o Doña Martha en su almacén de agroinsumos en Aguazul? En la cabeza o en un cuaderno.*  
>  
> *Y no es por falta de disciplina: es que el software que existe les exige internet permanente que se cae a cada rato en el departamento, pantallas llenas de formularios pequeños y una capacitación digital que no tienen tiempo de tomar.*  
>  
> *El resultado es devastador: pierden dinero con mercancía agotada o vencida sin enterarse, y peor aún: compran solos, bulto por bulto, pagando precios minoristas altísimos y fletes individuales frente a las grandes cadenas."*

---

## ⏱️ Minuto 0:45 - 1:45 | La Solución: NexoLlano

> *"Por eso creamos **NexoLlano**: la primera plataforma diseñada para unir el **inventario por voz sin internet** con una **central de compras colectiva** exclusiva para las MiPymes casanareñas.*  
>  
> *Nuestro sistema resuelve el problema en dos pasos:*  
> 1. **Inventario por voz 100% offline:** El tendero no digita nada. Oprime un botón y habla naturalmente: *'Llegaron veinte bultos de arroz casanareño y cinco de sal'*. Nuestro motor procesa el audio dentro del propio celular, comprende las unidades llaneras como bultos, arrobas, pacas o cargas, y le muestra una tarjeta de confirmación en pantalla.  
> 2. **Central de Compras Colectiva:** Al registrar el movimiento real, el sistema detecta cuándo el stock está bajo y consolida el pedido de Don Pedro con los demás comerciantes de su misma comuna o vereda. Juntos compran como un gran mayorista directo a los molinos, obteniendo hasta 18% de descuento y repartiendo el flete entre varios.*"

---

## ⏱️ Minuto 1:45 - 3:15 | Demostración en Vivo (La Prueba de Oro)

*(Proyectar en pantalla la terminal ejecutando `python3 backend/simulate_pitch_demo.py` o el navegador en `http://localhost:8000`)*

> **Demostración 1: Modo Avión (Cero Internet)**  
> *"Para demostrar que esto no es una presentación teórica ni un video pregrabado, activamos el **Modo Avión** en este momento. Sin una sola barra de señal ni Wi-Fi.*  
> *Voy a dictar una venta:*  
> 🎙️ *'Vendí quince bultos de arroz casanare y cinco bultos de sal'*  
> *Miren la pantalla:*  
> *El motor local interpretó la salida, extrajo las cantidades, reconoció 'bulto' y asoció el producto del catálogo regional con 100% de confianza. Al confirmar, el stock inmutable se calcula al instante.*"

> **Demostración 2: Alerta de Reposición y Reconexión**  
> *"El arroz y la sal han caído por debajo del umbral mínimo de seguridad. La app genera una alerta preventiva.*  
> *Ahora desactivamos el Modo Avión. El sistema detecta conexión y sincroniza los movimientos en segundo plano sin interrumpir la atención al cliente y sin duplicar transacciones gracias a nuestra arquitectura Ledger.*"

> **Demostración 3: El Poder de la Red (Compras Colectivas)**  
> *"Miren lo que ocurre en el servidor central de la Comuna 2 en Yopal:*  
> *Otras 3 tiendas vecinas también necesitan arroz. El sistema consolidó 70 bultos.*  
> *Al superar el volumen mayorista, el precio unitario baja de \$185.000 a \$155.000 y el flete de \$120.000 se reparte entre las 4 tiendas.*  
> **Resultado inmediato:** En este solo pedido, los comerciantes de la comuna ahorran **\$2.460.000 COP**. Dinero que va directo al bolsillo de las familias de Casanare.*"

---

## ⏱️ Minuto 3:15 - 4:15 | Seguridad, Sostenibilidad y TRL 4-5

> *"NexoLlano cumple estrictamente con la **Ley 1581 de 2012** (Habeas Data Colombia), minimizando datos personales y protegiendo la información con cifrado TLS 1.2+.*  
> *Para los comerciantes, la aplicación de inventario es y seguirá siendo **gratuita**, asegurando cero fricción en la adopción.*  
> *La sostenibilidad se fundamenta en convenios por volumen con los molinos y distribuidores aliados, y en la articulación con la Dirección TIC de la Gobernación de Casanare.*  
>  
> *Señores del jurado: NexoLlano transforma el comercio tradicional de Casanare desde la voz del comerciante hasta la economía colaborativa del departamento. Muchas gracias."*

---

## 🛡️ Preguntas Frecuentes del Jurado (Q&A de Defensa)

### 1. ¿Cómo garantizan que funcione en veredas sin señal?
> *Todo el motor de transcripción y el intérprete NLP de reglas heurísticas corren de forma nativa en el dispositivo. No enviamos audio a la nube (ahorrando datos móviles y batería). Los movimientos se almacenan en una base de datos local SQLite tipo libro mayor inmutable y se sincronizan automáticamente cuando el comerciante tiene señal o llega a su casa con Wi-Fi.*

### 2. ¿Qué pasa si hay mucho ruido en la tienda o música de fondo?
> *Por diseño de usabilidad, NexoLlano incluye una **pantalla de confirmación obligatoria** de un solo toque. El usuario ve exactamente lo entendido y puede ajustar la cantidad con un simple selector antes de que el movimiento se guarde.*

### 3. ¿Cómo manejan los conflictos si dos dispositivos registran inventario sin internet?
> *Implementamos el patrón **Event Sourcing / Ledger**. No modificamos un campo de 'stock total' directamente, sino que cada transacción es un registro de entrada o salida con UUID único y marca de tiempo UTC. Al sincronizar con el servidor, las operaciones se integran en orden sin sobreescribir ni perder transacciones.*
